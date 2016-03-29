# Change Log

29/03/2016
* SP ahora es independiente.

18/03/2014
* Remover rtrim(docId) ya que no es necesario para campos int.
* Cambio de single comment a block comment en el bloque informativo del codigo.

03/04/2014
* Mejora en el script radicalmente. Se consolidaron 2 casos:

    1.Donde el documento cerrado por Barcode hay LineNum repetidos se consolidan las lineas repetidas se suman itmQty y itmQty1.

    2. Donde el documento cerrado por Barcode no aya LineNum repetidos se respete cada linea con su valor asignado.

13/08/2014
* Reforzamos la relacion entre alias (documento maestro) y tabla actual (documento manual) para que
sum(T2.itmQty) no sume la cantidad de articulos en alias.

28/01/2015
* Unificar B1BBIL para todos los BarcodeBox utilizando SERVSAPDB.
* Filtro wheId para evitar conflicto con otros docNum.