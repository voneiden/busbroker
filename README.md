# busmaster2000

Client
* Module
    * Route
    
    
Data arrives from socket 
-> transform
-> redeliver to interested parties



```plantuml
@startuml
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

[Client] ..> [Router Manager] : SUB
[Client] ..> [Router] : PUB
[Router] ..> [ClientRoute] : PUB
[Socket] .down.> [Client] : RECV
[ClientRoute] .up.> [Socket] : SEND
[Main] -> [Server]
[Main] -> [Router Manager]
@enduml
```


Consider a simpler v2

* RequestQueue is derived in main, provided to sockets, handled by router
* Sockets create their own ResponseQueue and provide it to the router when subscribing

```plantuml
@startuml
[Main] -down-> [TCPServer] : fork
[Main] -down-> [Router]
[TCPServer]
interface accept
[TCPServer] -> [accept]
[accept] -> [Socket1]
[accept] -> [Socket2]
interface RequestQueue
[Socket1] -down-> [RequestQueue]
[Socket2] -up-> [RequestQueue]
[RequestQueue] -> [Router]

interface Socket1ResponseQueue
interface Socket2ResponseQueue
[Router] -up-> [Socket1ResponseQueue]
[Router] -down-> [Socket2ResponseQueue]
[Socket1] <- [Socket1ResponseQueue]
[Socket2] <- [Socket2ResponseQueue]
@enduml
```
