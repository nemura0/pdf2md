---
title: "Programación Orientada a Objetos"
source: "slides.pdf"
pages: 7
converted: "2026-01-01"
tool: "pdf2md 1.0.0"
---

# Programación Orientada a Objetos

<!-- page 1 -->

## Clase 3: clases y objetos

<!-- page 2 -->

## Objetivos de la clase

- Comprender qué es una clase
  - Atributos y métodos
  - Encapsulación básica
- Crear objetos en Java y Python
- Leer código con atención

<!-- page 3 -->

## Una clase en Java

Cada objeto guarda su propio estado:

```
public class Punto {
    private double x;
    public double getX() {
        return x;
    }
}
```

<!-- page 4 -->

## Lo mismo en Python

```
class Punto:
    def __init__(self, x):
        self.x = x

    def get_x(self):
        return self.x
```

<!-- page 5 -->

## Resultados del curso

Promedios por unidad en el semestre anterior.

<!-- page 6 -->

## Evaluaciones

| Evaluación | Semana | Ponderación |
| --- | --- | --- |
| Prueba 1 | 5 | 30% |
| Prueba 2 | 10 | 30% |
| Proyecto final | 15 | 40% |

Se aprueba con nota 4,0 en cada una.

<!-- page 7 -->

## Resumen

- Una clase define estado y comportamiento
- Los objetos son instancias de una clase
- La próxima clase veremos herencia
