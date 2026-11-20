# Instalador GLPI SkanHawk

Aplicación de Windows desarrollada en PowerShell para facilitar el registro de computadores en GLPI y la actualización de sus campos personalizados.

## Descripción

El instalador permite recopilar información del equipo y datos administrativos mediante una interfaz gráfica. Posteriormente, realiza el proceso de inventario y registra la información correspondiente en GLPI.

## Funcionalidades

- Verificación e instalación de GLPI Agent 1.21 cuando sea necesario.
- Formulario gráfico para registrar la información administrativa del computador.
- Selección del tipo de propiedad: propio o rentado.
- Selección de empresa y tipo de dueño.
- Registro de torre, usuario y ubicación.
- Generación del archivo XML para el inventario.
- Espera y búsqueda del computador en GLPI después del inventario.
- Actualización de los campos personalizados configurados en GLPI Fields.
- Actualización y validación de la información registrada.

## Tecnologías

- PowerShell
- Windows Forms
- GLPI
- GLPI Agent
- Complemento Fields de GLPI
- PS2EXE (para generar el ejecutable de Windows)

## Estructura del repositorio

```text
Instalador-GLPI-SkanHawk/
│
├── .env.example
├── .gitignore
├── InstalarRegistrar-GLPI-WINDOWS.cmd
├── Registrar-Activo-GLPI-Fields.ps1
└── README.md
```

## Requisitos

- Equipo con Windows.
- Conectividad con el servidor GLPI.
- Permisos suficientes para instalar GLPI Agent, si no está instalado.
- GLPI configurado con los campos personalizados requeridos por el instalador.

## Configuración

El proyecto utiliza un archivo `.env` para definir los parámetros de conexión y los identificadores de las opciones configuradas en GLPI.

Para configurar el proyecto:

1. Utilizar `.env.example` como plantilla.
2. Crear un archivo local llamado `.env`.
3. Completar los valores de configuración correspondientes al entorno GLPI.
4. No publicar el archivo `.env` ni compartir sus credenciales.

## Ejecución

El proyecto puede ejecutarse mediante el script de PowerShell o mediante el ejecutable generado para Windows.

Para utilizar el ejecutable:

1. Abrir `Instalador-GLPI-SkanHawk.exe`.
2. Completar los datos solicitados en el formulario.
3. Confirmar el registro.
4. Esperar a que termine el proceso de inventario y actualización.
5. Verificar el resultado en GLPI.

## Seguridad

- El archivo `.env` contiene información de configuración y credenciales privadas.
- No subir el `.env` real al repositorio.
- No publicar ejecutables que contengan credenciales administrativas reales.
- Las credenciales incluidas dentro de un ejecutable generado con PS2EXE no están cifradas y pueden extraerse.

## Repositorio

[GitHub - Instalador GLPI SkanHawk](https://github.com/Leidy-dev-26/Instalador-GLPI-SkanHawk)

## Autor

**SkanHawk SAS**
