#!/bin/bash
#
# Resize primary EBS disk of EC2 instance specified via Name tag

TAG_NAME=$1
EXTRA_SIZE=$2

##############################################################################################
### FIND EC2 INSTANCE
##############################################################################################


#######################################
# Get properties of a running instance
# Globals:
#   TAG_NAME
# Arguments:
#   JMESPath query for a request
#######################################
function describe() {
  aws ec2 describe-instances \
    --filters Name=tag:Name,Values=${TAG_NAME} \
    --filters Name=instance-state-code,Values=16 \
    --query "Reservations[].Instances[].${1}" \
    --output text
}


DEVICE_NAME=$(describe "RootDeviceName")
echo "DeviceName = ${DEVICE_NAME}"

INSTANCE_ID=$(describe "InstanceId")
echo "InstanceId = ${INSTANCE_ID}"

INSTANCE_TYPE=$(describe "InstanceType")
echo "InstanceType = ${INSTANCE_TYPE}"

PUBLIC_IP=$(describe "PublicIpAddress")
echo "PublicIpAddress = ${PUBLIC_IP}"

AVAILABILITY_ZONE=$(describe "Placement.AvailabilityZone")
echo "AvailabilityZone = ${AVAILABILITY_ZONE}"

VOLUME_ID=$(describe \
              'BlockDeviceMappings[?DeviceName=='"'"${DEVICE_NAME}"'"'].Ebs.VolumeId')
echo "VolumeId = ${VOLUME_ID}"

VOLUME_SIZE=$(aws ec2 describe-volumes \
                --volume-ids ${VOLUME_ID} \
                --query "Volumes[].Size" \
                --output text)
echo "VolumeSize = ${VOLUME_SIZE}"

##############################################################################################
### BACKUP
##############################################################################################

SNAPSHOT_ID=$(aws ec2 create-snapshot --volume-id ${VOLUME_ID} --query "SnapshotId")
SNAPSHOT_ID=${SNAPSHOT_ID//\"/}
echo "SnapshotId = ${SNAPSHOT_ID}"


##############################################################################################
### MODIFY EBS VOLUME
##############################################################################################

NEW_SIZE=$(( ${VOLUME_SIZE}+${EXTRA_SIZE} ))
echo "NewSize = ${NEW_SIZE}"
aws ec2 modify-volume --volume-id ${VOLUME_ID} --size ${NEW_SIZE}

# Wait for 10 minutes whether the size got changed
for try in {1..10}; do
  case $(aws ec2 describe-volumes-modifications \
            --volume-ids ${VOLUME_ID} \
            --query "VolumesModifications[].ModificationState" \
            --output text) in
    completed)
      echo -e "\nVolume modification succedeed!"
      echo "Please wait for the filesystem resizing"
      break
      ;;
    failed)
      echo -e "\nVolume modification failed"
      echo "Please restore manually from the snapshot ${SNAPSHOT_ID}"
      exit 1
      ;;
    *)
      sleep 60
      ;;
  esac
done


##############################################################################################
### EXTEND THE FILESYSTEM
##############################################################################################

PARTITION_NUMBER=$(ssh ec2-user@${PUBLIC_IP} "lsblk -l -o MAJ:MIN,MOUNTPOINT ${DEVICE_NAME}" \
  | awk '{ if ($2=="/") {split($1, partition, ":")} } END {print partition[2]}')
echo -e "\nPartitionNumber = ${PARTITION_NUMBER}"

if [[ -n $(ssh ec2-user@${PUBLIC_IP} "df -T /" \
             | awk '{ if (NR>1 && $2=="xfs") print $1 }') ]]
then
  ssh ec2-user@${PUBLIC_IP} "sudo growpart ${DEVICE_NAME} ${PARTITION_NUMBER}"
  ssh ec2-user@${PUBLIC_IP} "sudo xfs_growfs -d /"
else
  echo -e "\nThe script operates only with xfs for now"
  echo "You should manually resize the filesystem mounted at root"
  echo "If you found yourself in trouble feel free to restore from snapshot ${SNAPSHOT_ID}"
fi


# TODO(apolivin): Automate restoration from the snaphost if the script fails (feature)

