# busmaster2000

Client
* Module
    * Route
    
    
Data arrives from socket 
-> transform
-> redeliver to interested parties



```plantuml
package IO {
    [Main]
    package "IO Net" {
        [Server] -> [Client]
        [Client] -> [ClientRoute]
        [Socket] <-down-> [Server]
    }
    package "IO Routing" {
        [Router Manager] -> [Router]   
    }

    package "IO Config" {
        [Config]
    }
}

package Pure {
}

[Client] ..> [Router Manager] : SUB
[Client] ..> [Router] : PUB
[Router] ..> [ClientRoute] : PUB
[Socket] .down.> [Client] : RECV
[ClientRoute] .up.> [Socket] : SEND
[Main] -> [Server]
[Main] -> [Router Manager]
@enduml
```
