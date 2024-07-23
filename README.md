 Running a docker container in Azure private virtual network (vnet) with public access
 The container must be in a manually created vnet if you want to do peering to another
 private network. In this config the subnet gives permission to use blob storage for
 the containe group.

# Design Architecture

```mermaid
graph TD
    PublicIP[Public IP]
    LoadBalancer[Load Balancer]
    BackendPool[Backend Pool]
    Vnet[vnet]
    LBRule[LB rule]
    Probe[Probe]
    Subnet[Subnet]
    ContainerGroup[Container group]
    DockerApp[Docker app]
    SecurityGroup[Security Group]

    PublicIP --> LoadBalancer
    LoadBalancer --> BackendPool
    BackendPool --> Vnet

    LoadBalancer --> LBRule
    LBRule --> Probe

    Vnet --> Subnet
    Subnet --> ContainerGroup
    ContainerGroup --> DockerApp

    Subnet --> SecurityGroup
    SecurityGroup --> DockerApp

    Probe -.-> BackendPool
```
