---
title: "Foundations of Computing"
source: "book-cm.pdf"
pages: 6
converted: "2026-01-01"
tool: "pdf2md 1.0.0"
---

# Foundations of Computing

<!-- page 1 -->

### Lecture notes for a first course

Prepared for the pdf2md test suite

<!-- page 2 -->

## Introduction

A computer is a machine that follows instructions without understanding them. This course studies what such machines can do, how quickly they can do it, and how to write programs that other people can read. The material assumes no previous experience beyond basic algebra and a willingness to work through examples by hand.

### Why study algorithms

Faster hardware does not rescue a poor method. Doubling the speed of a processor adds very little when the running time of a program grows exponentially with its input, while a better algorithm can turn an impossible task into a routine one. Learning to reason about cost is therefore worth more than learning any particular language.

Careful analysis also prevents wasted effort, because it reveals where a program spends its time before anyone starts to optimize. Measuring first is a comprehensive habit that pays for itself on every project, large or small.

#### A short history

Mechanical calculators came first, followed by programmable machines in the middle of the twentieth century. Compilers then allowed people to write in notation closer to mathematics, and that shift created the discipline this course belongs to.

### What you will learn

- How to state a problem precisely before solving it.
- How to estimate cost using simple counting arguments.
  - Counting loop iterations in nested code.
  - Comparing growth rates of common functions.
- How to choose a data structure that fits the task.

Each week follows the same routine, in this order:

1. Read the chapter before the lecture.
2. Solve the exercises marked as essential.
3. Discuss the remaining problems in the workshop.

<!-- page 3 -->

## Measuring cost

To compare methods we count basic operations rather than seconds, since counts do not depend on the machine. Growth rates describe how those counts change as the input becomes larger, and they are what we compare when we choose between two algorithms.

### Growth and notation

Let the input have size 𝑛 and suppose 𝛼 ≤ 𝑥2 holds for every step 𝑥𝑖.

The next equation gives the cost of the outer loop, and the one after it shows the closed form that we will derive in the workshop using a short induction argument.

𝑓(𝑥) = 𝛼𝑥2 + 𝛽𝑥 + 𝛾

𝑇𝑛 ≠ ∅ ⇒ ∑ 𝑖2 ≥ 0

𝑛 + 1 𝑅 =

2𝑛 − 1

When a formula has a stacked fraction, a linear form can lose its structure, so the page keeps an image of the equation next to the best linear form available.

### Common costs

The following table lists the cost of common operations on two structures.

| Operation | Array | Linked list |
| --- | --- | --- |
| Read by index | constant | linear |
| Insert at front | linear | constant |
| Search unsorted | linear | linear |

No structure wins on every operation, which is why choosing one starts by listing what the program does most often.

<!-- page 4 -->

## Programming in Java

Java organizes code into classes, and each class describes the state and behaviour of its objects. The following example shows a small class with one field, a constructor and a method that reads the field back.

```
public class Counter {
    private int value;

    public Counter(int start) {
        this.value = start;
    }

    public int next() {
        for (int i = 0; i < 2; i++) {
            value += i;
        }
        return value;
    }
}
```

The field is private, so other classes can only change the count by calling a method. Restricting access in this way lets the class keep its own rules true at all times.

### Reading the example

- The constructor runs once when the object is created.
- The method updates the state and returns the new value.

#### Exercises

1. Add a method that resets the counter to its starting value.
2. Explain why the field is not declared public.

Write your answers in plain language first and then translate them into code. Being able to explain a program is the most reliable sign that you understand it well.

<!-- page 5 -->

### Reading in two columns

The left column begins here with a sentence that continues across several short lines so reading order matters a great deal for the final output, and the left column ends right here.

The right column begins here and must come only after the whole left column has been read, even though both of them share the same baselines on the page, and the right column ends here.

After the columns, a full-width paragraph returns to a single column, which closes this short chapter and checks that the layout switches back correctly afterwards.

<!-- page 6 -->

## Closing remarks

The ideas in these notes come back in every later course. Revisit them whenever a program feels slower than it should, and start by writing down what you expect it to cost. Comparing that expectation with a measurement is how intuition gets built.

### Further reading

- Any standard textbook on algorithms and data structures.
- The documentation of the language you use every day.
