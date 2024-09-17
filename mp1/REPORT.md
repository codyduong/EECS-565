# Report

## Technical Details

This works via a trivial multithreaded search through all permutations of length K matching the key length, simply checking if that key with the
first N chars of first_word_length are a word in the dictionary. This is a relatively naive approach. It also does not terminate early, it will check A.. Z for the key length (to ensure exhaustiveness).

Some ideas were slowly implemented that caused speedup:
* Multithreading
  + Using chunks instead
* Remove I/O in loop
* Stream permutations (also solved memory overflow)

## Results

The solved ciphers are as follows (all times are completion of exhausitive search, not necessarily when key was found):
1. <block>`CAESARSWIFEMUSTBEABOVESUSPICION`<br>
  Key: `KS` <br>
  Time: `920.3µs` </block>
2. <block>`FORTUNEWHICHHASAGREATDEALOFPOWERINOTHERMATTERSBUTESPECIALLYINWARCANBRINGABOUTGREATCHANGESINASITUATIONTHROUGHVERYSLIGHTFORCES`<br>
  Key: `KEY` <br>
  Time: `15.0506ms` </block>
3. <block>`EXPERIENCEISTHETEACHEROFALLTHINGS`<br>
  Key: `IWKD` <br>
  Time: `288.9822ms` </block>
4. <block>`IMAGINATIONISMOREIMPORTANTTHANKNOWLEDGE`<br>
  Key: `KELCE`

  Time: `7.4339894s` <br>
5. <block>`EDUCATIONISWHATREMAINSAFTERONEHASFORGOTTENWHATONEHASLEARNEDINSCHOOL`<br>
  Key: `HACKER`

  Time: `192.6600093s` <br></block>
6. <block>`INTELLECTUALSSOLVEPROBLEMSGENIUSESPREVENTTHEM`<br>
  Key: `NICHOLS`

  Time: `5061.6390669s` <br>

## Afterthoughts

While the efficiencies implemented were simple options applicable to any problem (ie. multithreading), there are some possible other considerations.
* We do not need an exhaustive search, the rest of these rely on finding the key as soon as possible.
* We may be able to make assumptions about our keys. If we know keys are always a word then the problem space is vastly simpler (and faster).
  + The challenge is in ensuring our dictionary is "complete".
* We can use frequency analysis as well as the Friedman test to determine the key length (if not known), to choose which keys to test earlier.
* We can examine word frequency as well for possible repetitions in the encrypted text, depending on length can be correlated with real
  word frequency. If not it is still a useful tool to determine the key length (Kasiski examination).

As a language consideration: [Bend](https://github.com/HigherOrderCO/Bend) seems a promising application for deriving the parallel computations
with less explicit intervention.

## Running

This originally started as a `.hs` implementation, but I suck at writing haskell and could not properly utilize the multithreading to
solve the ciphers. So I swapped to `.rs` . The original `.hs` is preserved.

This requires the rust development toolchain. A makefile has been provided for your convenience. It may be desireable to configure
the optimization levels in `Cargo.toml` . See here: https://doc.rust-lang.org/book/ch14-01-release-profiles.html

```
make all
```
