# About

It is a script for resizing primary EBS volume of an EC2 instance specified by Name tag


# Requirements

- Bash
- Configured aws cli:
```
aws configure
```
- Access to your EC2 instance via SSH


# Usage

```
./resize.sh <tag> <extra size>
```

