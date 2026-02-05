
## Versión de las cargas de trabajo de .NET

Necesario para configuar el yml
```
C:\Users\fernando>dotnet workload --version
10.0.102
```

```
C:\Users\fernando>dotnet workload update

Manifiesto publicitario actualizado microsoft.net.workloads
No se encontró ninguna actualización de carga de trabajo.

La(s) carga(s) de trabajo se ha(n) actualizado correctamente: android ios maccatalyst maui-android maui-windows wasm-tools
```

```
C:\Users\fernando>dotnet workload list

Versión de carga de trabajo: 10.0.102

Id. de carga de trabajo instalada      Versión del manifiesto      Origen de la instalación
--------------------------------------------------------------------------------------------------------------------
android                                36.1.12/10.0.100            SDK 10.0.100, VS 18.2.11415.280, VS 17.14.36811.4
ios                                    26.2.10191/10.0.100         SDK 10.0.100, VS 18.2.11415.280, VS 17.14.36811.4
maccatalyst                            26.2.10191/10.0.100         SDK 10.0.100, VS 18.2.11415.280, VS 17.14.36811.4
maui-android                           10.0.1/10.0.100             SDK 10.0.100
maui-windows                           10.0.1/10.0.100             SDK 10.0.100, VS 18.2.11415.280, VS 17.14.36811.4
wasm-tools                             10.0.102/10.0.100           SDK 10.0.100, VS 17.14.36811.4

Use "dotnet workload search" para buscar cargas de trabajo adicionales para instalar.
```

```
C:\Users\fernando>dotnet workload search maui

Id. de carga de trabajo      Descripción
------------------------------------------------------------
maui                         .NET MAUI SDK for all platforms
maui-android                 .NET MAUI SDK for Android
maui-desktop                 .NET MAUI SDK for Desktop
maui-ios                     .NET MAUI SDK for iOS
maui-maccatalyst             .NET MAUI SDK for Mac Catalyst
maui-mobile                  .NET MAUI SDK for Mobile
maui-tizen                   .NET MAUI SDK for Tizen
maui-windows                 .NET MAUI SDK for Windows
```

```
C:\Users\fernando>dotnet --version
10.0.102
```