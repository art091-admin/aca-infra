#!/bin/bash

CONFIG_FILE=~/.aws/config
REGION=""

while IFS=' = ' read key value
do
    if [[ $key == \[*] ]]; then
        section=$key
    elif [[ $value ]] && [[ $section == '[default]' ]]; then
        if [[ $key == 'region' ]]; then
            DEFAULT_REGION=$value
	fi    
    fi
done < $CREDENTIALS_FILE

if [[ -z "$DEFAULT_REGION" ]]; then
	REGION=$REGION
else
	REGION=$DEFAULT_REGION
fi

#Create VPC with tags
echo "Creating VPC...."

CREATED_VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)
VPC_TAGS=$(aws ec2 create-tags --resources $CREATED_VPC_ID --tags Key=Name,Value=VPC-Created-By-CLI)
if [ $? -eq 0 ]; then
	echo "VPC is successfully created"
else
	echo "Failed creating"
	exit 1
fi	
#echo $CREATED_VPC_ID

echo "Creating Subnets for VPC: $CREATED_VPC_ID ...."
#Create Subnets

CREATED_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $CREATED_VPC_ID --cidr-block 10.0.1.0/24 --query Subnet.SubnetId --output text)
SUBNET_TAGS=$(aws ec2 create-tags --resources $CREATED_SUBNET_ID --tags Key=Name,Value=Subnet-VPCid-$CREATED_VPC_ID)

if [ $? -eq 0 ]; then
	echo "Subnet is successfully created"
else
	echo "Failed creating"
	$(aws ec2 delete-vpc --vpc-id $CREATED_VPC_ID)
	exit 1
fi	

echo "Creating Internet Gateway...."
#Create Internet Gateway

CREATED_INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
SUBNET_TAGS=$(aws ec2 create-tags --resources $CREATED_INTERNET_GATEWAY_ID --tags Key=Name,Value=IGW-VPCid-$CREATED_VPC_ID)
$(aws ec2 attach-internet-gateway --internet-gateway-id $CREATED_INTERNET_GATEWAY_ID --vpc-id $CREATED_VPC_ID)

if [ $? -eq 0]; then
	echo "InternetGateway is successfully created"
else
	echo "Failed creating"
	$(aws ec2 delete-vpc --vpc-id $CREATED_VPC_ID)
	exit 1
fi	


echo "Creating Route Table...."

#Create Route Table

CREATED_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $CREATED_VPC_ID --query RouteTable.RouteTableId --output text)
ROUTE_TABLE_TAGS=$(aws ec2 create-tags --resources $CREATED_ROUTE_TABLE_ID --tags Key=Name,Value=RouteTable-$CREATED_VPC_ID)
CREATED_ROUTE=$(aws ec2 create-route --route-table-id $CREATED_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $CREATED_INTERNET_GATEWAY_ID)
$(aws ec2 associate-route-table --route-table-id $CREATED_ROUTE_TABLE_ID --subnet-id $CREATED_SUBNET_ID)

if [ $? -eq 0 ]; then
	echo "Route Table is successfully created"
else
	echo "Failed creating"
	$(aws ec2 delete-vpc --vpc-id $CREATED_VPC_ID)
	exit 1
fi	


#Creating Security Group
echo "Creating Security Group"

SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name MyVPCSecurityGroup --description "Security Group For My VPC" --vpc-id $CREATED_VPC_ID --query GroupId --output text) && echo "Security Group is successfully created" || echo "Failed creating $(aws ec2 delete-vpc --vpc-id $CREATED_VPC_ID)"
$(aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0)

if [ $? -eq 0 ]; then
	echo "The Vpc is successfully  created"
else
	echo "Failed creating $(aws ec2 delete-vpc --vpc-id $CREATED_VPC_ID)"
	exit 1
fi



#Launching EC2 Instance

echo "Creating EC2 Instance"
INSTANCE_ID=$(aws ec2 run-instances --image-id ami-0fc5d935ebf8bc3bc --count 1 --instance-type t2.micro --key-name lesson-3-virginia --security-group-ids $SECURITY_GROUP_ID --subnet-id $CREATED_SUBNET_ID --network-interfaces '[{"DeviceIndex":0,"AssociatePublicIpAddress":true}]' --query Instances.InstanceId --output text)
INSTANCE_TAGS=$(aws crate-tags --resources $INSTANCE_ID --tags Key=Name,Value=EC2-VPCid-$CREATED_VPC_ID)
echo "Done"
