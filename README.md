# zigdragon

`zigdragon` is a Heighway curve generator, written in `Zig`. I wrote this as a fun project after completing the Ziglings exercises.

```
                               ####    ####
                               #####   #####
                             ####### #######
                             #####   #####
                              #################
     ##  ##                    #################
    ### ###                  ######## ### ######
    #########                ######## ##  ####
    #########          ####   #######       ###
 ## ####   ##          #####   ######       ####
### ####  ###        ####### #### ###    ## ####
######    ##         #####   #### ##     #####
#######               ###########         ####
########               ############
  ######             ##############
  ####               ################
    #######    ####   ###############
 ## ########   #####   ##############
### ######## ####### ############ ###
##########   #####   ############ ##
#################################
###################################
  ### ### ########### ### #########
  ##  ##  ########### ##  ###########
            #########       #########
         ## #########    ## #########
        ### ##### ###   ### ##### ###
        ######### ##    ######### ##
        #########       #########
        #########       #########
          ### ###         ### ###
          ##  ##          ##  ##
```

## Build

Built using [Zig](https://codeberg.org/ziglang/zig) version `0.16.0`

`zig build-exe zigdragon.zig -O ReleaseSmall -fstrip -fsingle-threaded`

Or using the Nix flake: `nix build`

## Usage

```
Usage: zigdragon [-rSD] [-n <iteration>]...

zigdragon is a Heighway curve generator.

Options:
  -r, --right               Generate a right folding curve instead of left
  -S, --sequence            Output the sequence of folds
  -D, --draw                Draw the fractal (drawn by default)
  -n <iteration>            Number of iterations the pattern is folded
                            (default: 10)
  -x, --scale <len>         Segment length between each fold (default: 1)
  -b, --brush <char>        Ascii character to draw with (default: '#')
  -s, --start <direction>   Cardinal direction to start the curve with
                            e.g. N, S, E, W (default: S)
  -h, --help                Show help
```
