# Guía de Contribución

¡Gracias por tu interés en contribuir a **Hauyna WebSocket**!  
Este documento describe las pautas para reportar errores, crear pull requests, mantener un estilo de código coherente y, en general, colaborar de forma efectiva en este proyecto.

---

## Reportando Issues

1. **Buscar Duplicados**  
   Antes de abrir un _issue_, revisa si alguien más ha reportado un problema similar.
   - Usa la barra de búsqueda en [Issues](../../issues) para encontrar reportes relacionados.
   - Si encuentras un _issue_ similar, añade tu información como comentario en lugar de duplicar.

2. **Crear un Nuevo Issue**  
   Si no existe un _issue_ que coincida con tu problema:
   - Proporciona un **título claro** y descriptivo.
   - Describe el **comportamiento esperado** y el **comportamiento actual**.
   - Incluye pasos para **reproducir** el problema (instrucciones, código mínimo, entorno, etc.).
   - Comparte cualquier **log** o **traza de error** relevante.
   - Indica tu **versión** de Crystal, la **versión** de Hauyna WebSocket y el sistema operativo en el que te encuentras.

3. **Etiquetas y Triage**  
   - Un mantenedor revisará tu reporte, lo etiquetará y dará seguimiento.
   - Si requieres más información, se te solicitarán detalles adicionales.

---

## Pull Requests

1. **Pequeñas Mejoras o Correcciones**  
   - Para problemas menores (ej. correcciones tipográficas, ajustes de estilo), crea un **pull request** directamente con una descripción concisa.
   - Asegúrate de que las pruebas existentes no fallen tras tu cambio.

2. **Grandes Cambios o Nuevas Características**  
   - Crea primero un _issue_ o discútelo con los mantenedores para acordar el enfoque.
   - Asegúrate de que tu propuesta sea coherente con la **hoja de ruta** y los lineamientos de arquitectura del proyecto.

3. **Proceso para Crear un Pull Request**  
   - **Haz un fork** del repositorio y crea tu rama con un nombre descriptivo (por ejemplo, `fix/timeout-issue` o `feat/channel-optimizations`).
   - **Realiza tus cambios** y **agrega pruebas** que verifiquen la funcionalidad o corrijan el error.
   - Asegúrate de que todas las pruebas existentes **pasen** antes de enviar el PR.
   - Redacta un **resumen claro** en la descripción del PR explicando tus cambios.
   - Referencia el _issue_ relevante si aplica (por ejemplo, `Closes #123`).

4. **Revisión y Merge**  
   - Los mantenedores revisarán tu PR, dejarán comentarios y sugerencias si es necesario.
   - Ajusta el PR según el _feedback_.  
   - Una vez aprobado y sin conflictos, se realizará el **merge**.

---

## Estilo de Código

Para mantener la consistencia y facilitar la revisión, estas son las pautas sugeridas:

1. **Formato y Convenciones**  
   - Sigue el **estilo oficial** de Crystal (espacios en lugar de tabs, 2 espacios de indentación, etc.).
   - Nombres de métodos y variables en `snake_case`.
   - Nombres de clases y módulos en `CamelCase`.

2. **Documentación**  
   - Añade comentarios en **métodos** o **secciones complejas** de tu código.
   - Para documentación mayor, utiliza markdown en archivos aparte (`docs/`).

3. **Pruebas**  
   - Cada nueva funcionalidad o corrección de error debería venir acompañada de pruebas en la carpeta `spec/`.
   - Estructura los **describe**, **it** y **context** de manera clara.
   - Usa nombres descriptivos para los ejemplos de prueba.

4. **Commits**  
   - Realiza _commits_ atómicos y con mensajes claros en **inglés o español**.
   - Evita mensajes de _commit_ genéricos como `fix stuff`. Sé conciso y directo (`Fix concurrent access in Presence module`).

5. **Linter / Formateador**  
   - Si existe un formateador automático (por ejemplo `crystal tool format`), úsalo antes de hacer _commit_ o _push_.
   - Revisa la configuración del proyecto (si se provee) para garantizar uniformidad en el formato.

---

## Comunicación

- Para consultas rápidas, sugerencias u otras discusiones:
  - Usa la sección de [Discussions](../../discussions) si el proyecto la tiene habilitada, o crea un _issue_ con etiqueta `question`.
  - También puedes preguntar en redes o foros de Crystal, mencionando este repositorio y detallando tu duda.

- Para propuestas mayores o cambios de arquitectura, abre un *issue* con la etiqueta `proposal` para debatirlo con la comunidad y los mantenedores.

---

## ¡Gracias!

Tu contribución es esencial para seguir mejorando **Hauyna WebSocket** y mantenerlo estable y útil.  
¡Gracias por ayudar a hacer de este proyecto algo mejor para la comunidad Crystal!
