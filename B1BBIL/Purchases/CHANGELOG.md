# Change Log

31/08/2015
- Mejoras drasticas a la consulta de coleccion de detalles para eliminar "redundant lookup" en las columnas itmPrice & itmTax.

    Mas detalle ver https://vimeo.com/137871733

28/07/2015
- Refactorizacion de sentencias, minusculas a mayusculas.
- Identificador "@" en comentarios.
- Formato de fecha en @history de "/" a ".".
- Manejo en el caso de Deadlock re-intentar 3 veces.

28/01/2015
- Unificar B1BBIL para todos los BarcodeBox utilizando SERVSAPDB.
- Filtro wheId para evitar conflicto con otros docNum.

03/05/2014
- Fix left join evitar que se dupliquen lineas al unir documentos con origen B al origen C.

21/03/2014
- Se agrega isnull(_exp, 0) en el campo itmTax para aliviar caso donde el add-on no inserta datos al ERP por el campo ser nulo.