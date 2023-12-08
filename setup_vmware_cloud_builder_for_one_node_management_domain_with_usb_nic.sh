#!/bin/bash

green='\E[32;40m'

cecho() {
        local default_msg="No message passed."
        message=${1:-$default_msg}
        color=${2:-$green}
        echo -e "$color"
        echo -e "$message"
        tput sgr0

        return
}

cecho "Updating VMware Cloud Builder to support 1-Node Management Domain ..."
echo "bringup.mgmt.cluster.minimum.size=1" >> /etc/vmware/vcf/bringup/application.properties

cecho "Detecting version of VMware Cloud Builder Version ..."
rpm -qa | grep 'vcf-bringup-ui-5.0.0' > /dev/null 2>&1
if [ $? -eq 0 ]; then
        VCF_VERSION="5.0"
fi

rpm -qa | grep 'vcf-bringup-ui-5.1.0' > /dev/null 2>&1
if [ $? -eq 0 ]; then
        VCF_VERSION="5.1"
fi

if [[ ${VCF_VERSION} == "5.0" ]] || [[ ${VCF_VERSION} == "5.1" ]]; then
        echo "feature.vcf.bringup.vlcm=true" >> /etc/vmware/vcf/bringup/application.properties

        cecho "VMware Cloud Builder Version is ${VCF_VERSION} ..."
        case ${VCF_VERSION} in
                "5.0")
                NEW_VSPHERE_SDK_WRAPPER_NAME="vsphere-plugin-1.0.0-vcf50.jar"
                NEW_VSPHERE_PLUGIN_NAME="vsphere-sdk-wrapper-1.0.0-vcf50.jar"
                ;;
                "5.1")
                NEW_VSPHERE_SDK_WRAPPER_NAME="vsphere-plugin-1.0.0-vcf51.jar"
                NEW_VSPHERE_PLUGIN_NAME="vsphere-sdk-wrapper-1.0.0-vcf51.jar"
                ;;
        esac

        if [[ -e ${NEW_VSPHERE_SDK_WRAPPER_NAME} ]] && [[ -e ${NEW_VSPHERE_PLUGIN_NAME} ]]; then
                cecho "Replaing VMware Cloud Builder vsphere-sdk-wrapper and vsphere-plugin jar for non-PCIe NIC ..."

                OLD_VSPHERE_SDK_WRAPPER_NAME=$(ls /opt/vmware/bringup/webapps/bringup-app/lib/ | grep "^vsphere-sdk-wrapper")
                OLD_VSPHERE_PLUGIN_NAME=$( ls /opt/vmware/bringup/webapps/bringup-app/lib/ | grep "^vsphere-plugin")

                chown vcf_bringup:vcf ${NEW_VSPHERE_SDK_WRAPPER_NAME}
                chown vcf_bringup:vcf ${NEW_VSPHERE_PLUGIN_NAME}
                chmod 740 ${NEW_VSPHERE_SDK_WRAPPER_NAME}
                chmod 740 ${NEW_VSPHERE_PLUGIN_NAME}
                cp /opt/vmware/bringup/webapps/bringup-app/lib/${OLD_VSPHERE_SDK_WRAPPER_NAME} /opt/vmware/bringup/webapps/bringup-app/lib/${OLD_VSPHERE_SDK_WRAPPER_NAME}.bak
                cp /opt/vmware/bringup/webapps/bringup-app/lib/${OLD_VSPHERE_PLUGIN_NAME} /opt/vmware/bringup/webapps/bringup-app/lib/${OLD_VSPHERE_PLUGIN_NAME}.bak
                mv ${NEW_VSPHERE_SDK_WRAPPER_NAME} /opt/vmware/bringup/webapps/bringup-app/lib/${OLD_VSPHERE_SDK_WRAPPER_NAME}
                mv ${NEW_VSPHERE_PLUGIN_NAME} /opt/vmware/bringup/webapps/bringup-app/lib/${OLD_VSPHERE_PLUGIN_NAME}
        fi
fi

cecho "Restart VMware Cloud Builder service ..."
systemctl restart vcf-bringup.service

cecho "Umounting /mnt/iso ..."
umount /mnt/iso

cecho "Creating overlay directories ..."
mkdir -p /overlay/{upper,work}
mkdir -p /root/oldiso

cecho "Re-mounting sddc-foundation-bundle.iso to /root/oldiso ..."
mount -o loop /opt/vmware/vcf/iso/sddc-foundation-bundle.iso /root/oldiso

ORIGINAL_NSX_OVA_PATH=$(find /root/oldiso -type f -name "nsx-unified*.ova")
NEW_NSX_OVA_PATH="/overlay/upper/${ORIGINAL_NSX_OVA_PATH#/root/oldiso/}"
NEW_NSX_OVF_PATH="${NEW_NSX_OVA_PATH%.*}.ovf"

cecho "Converting original NSX OVA to OVF ..."
mkdir -p "$(dirname "${NEW_NSX_OVA_PATH}")"
ovftool --acceptAllEulas --allowExtraConfig --allowAllExtraConfig --disableVerification ${ORIGINAL_NSX_OVA_PATH} ${NEW_NSX_OVF_PATH}
rm "${NEW_NSX_OVA_PATH%.ova}.mf"

cecho "Removing memory reservation from NSX OVA ..."
sed -i '/        <rasd:Reservation>.*/d' ${NEW_NSX_OVF_PATH}

cecho "Converting modified NSX OVF to OVA ..."
ovftool --acceptAllEulas --allowExtraConfig --allowAllExtraConfig --disableVerification ${NEW_NSX_OVF_PATH} ${NEW_NSX_OVA_PATH}

cecho "Cleaning up ..."
rm "${NEW_NSX_OVA_PATH%.ova}.ovf"
rm $(dirname "${NEW_NSX_OVA_PATH}")/*.vmdk

cecho "Update permisisons in /mnt/iso & /overlay directory ..."
chown nobody:nogroup -R /overlay/upper
chmod -R 755 /overlay/upper

cecho "Enabling overlay module & mounting new overlay directories ..."
modprobe overlay
mount -t overlay -o lowerdir=/root/oldiso,upperdir=/overlay/upper,workdir=/overlay/work overlay /mnt/iso

cecho "VMware Cloud Builder 1-Node Setup script has completed ..."
