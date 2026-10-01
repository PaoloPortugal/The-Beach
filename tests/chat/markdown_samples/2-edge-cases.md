# Edge cases and hostile input

## BBCode injection (must all show as literal text)

Plain: [b]not bold[/b] [color=red]not red[/color] [img]https://example.com/x.png[/img]
A fake link: [url=https://evil.example]click me[/url] and [url]https://evil.example[/url]
Escaped-looking: [lb] [rb] [/b] [font_size=90]huge?[/font_size]
Inside inline code: `[b]still literal[/b]` and ``code with ` backtick``

```text
[img]https://example.com/tracker.png[/img]
[url=https://evil.example]in a code block[/url]
```

## Links

- Safe: [Godot docs](https://docs.godotengine.org), <https://example.com/auto>, bare https://example.com/path?q=1.
- Wikipedia style (parens): https://en.wikipedia.org/wiki/Markdown_(disambiguation)
- In parens (https://example.com/inside) stays clean.
- Unsafe scheme: [run me](javascript:alert(1)) and [local file](file:///C:/Windows/win.ini)
- Relative: [README](../README.md)
- Bracket in URL: [tricky](https://example.com/a]b[img]c)
- Image (never loaded): ![a tracking pixel](https://example.com/pixel.png)
- Mail: <mailto:someone@example.com>

## Emphasis

*italic* _italic_ **bold** __bold__ ***both*** ~~struck~~ **bold with *italic* inside**
snake_case_names and __init__ and 2*3*4 and a * b * c stay plain.
**unclosed bold and *unclosed italic
Escaped: \*not italic\* \`not code\` \[not a link\](nope)

## Lists

1. First
2. Second
   - nested bullet
     - deeper bullet
       1. deep ordered
3. Third, after nesting

5. A list that starts at five
6. Six

* star bullets
+ plus bullets

## Quotes

> Level one
> > Level two with `code` and a list:
> > - item
>
> Back to one.

## Table with pipes in code

| Operator | Meaning |
|:--|--:|
| `a \| b` | bitwise or |
| `a && b` | logical and |
| missing cell |

## Long line

This is a very long line without any natural break points: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.

```python
really_long_line = "this line should scroll horizontally, not wrap: " + "x" * 200 + " and keep going and going and going"
```

Hard break with two spaces  
next line. Backslash break\
next line.

## Unclosed fence (as while streaming)

```js
const stillWriting = true;
