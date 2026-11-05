---
title: "Libro de Dibujos"
source: "drawing-book.pdf"
pages: 3
converted: "2026-01-01"
tool: "pdf2md 1.0.0"
---

# Libro de Dibujos

<!-- page 1 -->

Un libro corto para probar lo que se dibuja.

<!-- page 2 -->

## Clases y objetos

Una clase se dibuja como una caja con sus atributos:

![Figure](drawing-book_assets/p0002-01.png)

```text
                                                                     Una venta
                       Persona
              -rut:String                      compra                Celular
prod          +getRut():String                              -modelo:String
                                                   registrado
```

Despues del diagrama sigue el texto normal de la pagina.

Este parrafo tiene codigo sombreado en varias de sus lineas pero no es un dibujo porque sus lineas salen muy lejos de cada uno de esos rectangulos pequenos que hay detras de algunas palabras y eso es propio de un parrafo de texto corriente.

| Nombre | Tamano | Descripcion |
| --- | --- | --- |
| byte | 1 byte | Un entero corto |
| double | 8 bytes | Un decimal doble |

Un entorno de desarrollo[^p2-1], es la herramienta que usaremos.

El siguiente es el compilador[^p2-2], que traduce el codigo.

Este otro parrafo empieza en esta pagina y no termina en ella porque sigue en la siguiente, donde se acaba la frase.

[^p2-1]: IDE: entorno integrado de desarrollo

[^p2-2]: Se llama javac

<!-- page 3 -->

Lo mismo en los dos lenguajes:

```
1 x = 15
2
3 if x < 30:
4   print(x)
```

```
1 public class Main
2 {
3     int x = 15;
4     void run()
5     {
6         print(x);
7     }
8 }
```

Y una tabla de marcas:

| Nivel | Clase |
| --- | --- |
| public | ✔ |
| private | ✔ |
