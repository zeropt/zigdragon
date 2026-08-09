# zigdragon

`zigdragon` is a Heighway curve generator, written in `Zig`. I wrote this as a fun exercise after completing the Ziglings course.

![zigdragon example](img/example.png)

## Build

Built using [Zig](https://codeberg.org/ziglang/zig) version `0.16.0`

Download the source and run:

`zig build-exe zigdragon.zig -O ReleaseSmall -fstrip -fsingle-threaded`

Or using the Nix flake:

`nix build github:zeropt/zigdragon`

## Usage

```
Usage: zigdragon [-fm] [-s/--style <style>] [-n <iteration>]...

zigdragon is a Heighway curve generator.

Drawing Styles:
  none       no drawing
  arcs       unicode light box characters with rounded corners
  ascii      plain ascii using the [--brush] character
  blocks     unicode block element patterns
  box        (default) unicode light box drawing characters
  braille    unicode braille patterns
  doublebox  unicode double box drawing characters
  heavybox   unicode heavy box drawing characters

Options:
  -f, --folds                 Print the sequence of folds
  -m, --mirror                Generate a right instead of left-handed curve
  -s, --style <style>         Drawing style (see the styles listed above)
  -n <iteration>              Number of iterations the pattern is folded,
                              iteration < 24 (default: 10)
  -x, --scale <len>           Segment length between each fold (default: 1)
  -d, --direction <heading>   Cardinal direction to start the curve with
                              e.g. N, S, E, W (default: S)
  -b, --brush <char>          Ascii character to draw with in 'ascii' style
                              (default: '#')
  -h, --help                  Show help
```
