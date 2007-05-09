\ See license at end of file
purpose: decode IMA/DVI ADPCM .wav file

2 value #output-ch                      \ Number of output channels
0 value audio-ih                        \ /audio ihandle
0 value /pcm-output                     \ Size of uncompressed buffer
defer (play-pcm)

: $call-audio  ( ... method -- ... )  audio-ih $call-method  ;

\ Uncompressed data format:
\   16-bit Left, 16-bit Right, ...
\
\ Compressed data format:
\   nibbles	0.hi 0.lo  1.hi 1.lo  2.hi 2.lo  3.hi 3.lo  4.hi 4.lo  5.hi 5.lo ...
\               L1   L0    L3   L2    L5   L4    L7   L6    R1   R0    R3   R2   ...

\ Work on one channel at a time.

0 value val-pred			\ predicted value
0 value index				\ current step change index
0 value in-val				\ place to keep (encoded) input value
0 value in-skip				\ # bytes to skip on channel input
0 value out-skip			\ # bytes to skip on channel output
0 value buf-skip			\ toggle flag for writing values

0 value #ch                             \ # channels
0 value blk-size                        \ # bytes per compressed block
0 value #sample/blk                     \ (blk-size-(#ch*4)) + 1

decimal
create index-table -1 , -1 , -1 , -1 , 2 , 4 , 6 , 8 ,
                   -1 , -1 , -1 , -1 , 2 , 4 , 6 , 8 ,

create stepsize-table			\ 89 entries
    7 , 8  , 9 , 10 , 11 , 12 , 13 , 14 , 16 , 17 ,
    19 , 21 , 23 , 25 , 28 , 31 , 34 , 37 , 41 , 45 ,
    50 , 55 , 60 , 66 , 73 , 80 , 88 , 97 , 107 , 118 ,
    130 , 143 , 157 , 173 , 190 , 209 , 230 , 253 , 279 , 307 ,
    337 , 371 , 408 , 449 , 494 , 544 , 598 , 658 , 724 , 796 ,
    876 , 963 , 1060 , 1166 , 1282 , 1411 , 1552 , 1707 , 1878 , 2066 ,
    2272 , 2499 , 2749 , 3024 , 3327 , 3660 , 4026 , 4428 , 4871 , 5358 ,
    5894 , 6484 , 7132 , 7845 , 8630 , 9493 , 10442 , 11487 , 12635 , 13899 ,
    15289 , 16818 , 18500 , 20350 , 22385 , 24623 , 27086 , 29794 , 32767 ,
hex

0 value 'index-table
0 value 'stepsize-table

: init-ch-vars  ( in out -- in' out' )
   over <w@ dup to val-pred             \ The first entry is the initial value
   over w!
   over 2 + c@ to index                 \ And the initial index
   out-skip +
   swap in-skip + swap
;

code adpcm-decode-sample  ( in out sample# -- in' out' )
   \ Get the delta value
   eax pop                              ( in out )
   7 # eax and 0=  if
      4 [esp] ecx mov                   \ Read the next 4 bytes
      0 [ecx] ebx mov
      'user in-skip ecx mov             \ Increment in to the next data for the channel
      ecx 4 [esp] add
   else
      'user in-val ebx mov
      ebx 4 # shr
   then
   ebx 'user in-val mov                 \ Save the input data
   h# f # ebx and                       \ delta

   \ Compute difference and new predicated value
   \ Computes 'vpdiff = (delta+0.5)*step/4', but see comment in adpcm-coder.
   'user index eax mov                  \ index
   'user 'stepsize-table ecx mov        \ address of stepsize-table
   0 [ecx] [eax] *4 ecx mov             \ step = stepsize-table[index]

   ecx eax mov  eax 3 # shr             \ vpdiff

   4 # bl test 0<>  if   ecx eax add  then
   2 # bl test 0<>  if   ecx edx mov  edx 1 # shr  edx eax add  then
   1 # bl test 0<>  if   ecx edx mov  edx 2 # shr  edx eax add  then

   \ Clamp down output value
   'user val-pred edx mov
   8 # ebx test 0=  if
      eax edx add
   else
      eax edx sub
   then
   d# 32767 # edx cmp >  if  d# 32767 # edx mov  then
   d# -32768 # edx  cmp <  if  d# -32768 # edx mov  then
   edx 'user val-pred mov               \ Update valpred
   0 [esp] eax mov                      \ out
   op: dx 0 [eax] mov                   \ [out] = valpred
   'user out-skip eax mov
   eax 0 [esp] add                      \ Advance out pointer

   \ Update index value
   'user 'index-table eax mov           \ address of index-table
   0 [eax] [ebx] *4 eax mov             \ index-table[delta]

   'user index eax add                  \ index+index-table[delta]
   0 # eax cmp <  if  eax eax xor  then
   d# 88 # eax cmp >  if  d# 88 # eax mov  then
   eax 'user index mov                  \ Update index
c;

: adpcm-decode-ch  ( in out #sample -- )
   0  ?do
      i adpcm-decode-sample             ( in' out' )
   loop  2drop
;

: adpcm-decode-blk  ( in out #sample -- )
   #ch #output-ch min 0  ?do            ( in out #sample )
      2 pick i /l * +                   ( in out #sample in' )
      2 pick i /w * +                   ( in out #sample in out' )
      init-ch-vars			( in out #sample in' out' )
      2 pick 1-                         ( in out #sample in out #sample-1 )
      adpcm-decode-ch                   ( in out #sample )
   loop  3drop                          ( )
;

: adpcm-decoder  ( in out #sample #ch blk-size -- )
   index-table to 'index-table
   stepsize-table to 'stepsize-table

   dup to blk-size                      ( in out #sample #ch blk-size )
   over 4 * - 2* over / 1+ to #sample/blk ( in out #sample #ch )
   dup to #ch                           ( in out #sample #ch )
   /l * to in-skip                      ( in out #sample )
   #output-ch /w * to out-skip          ( in out #sample )

   begin  dup 0>  while                 ( in out #sample )
      3dup #sample/blk min adpcm-decode-blk
      rot blk-size +                    ( out #sample in' )
      rot #sample/blk #output-ch * wa+  ( #sample in out' )
      rot #sample/blk -                 ( in out #sample' )
   repeat  3drop
;

\ Decode a .wav file
\
\ .wav file format:
\ "RIFF" L<len of file> "WAVE"
\ "fmt " L<len of fmt data> W<compression code> W<#channels> L<sample rate>
\        L<bytes/second>] W<block align> W<bits/sample> W<extra bytes>
\        W<#samples/block>]
\ "fact" L<len of fact> L<#samples>
\ "data" L<len of data> <blocks of data>
\
\ Each <block of data> contains:
\        W<sample> B<index> B<0> per channel
\        (block size - 1) samples of compressed data

0 value wav-fmt-adr
0 value wav-fact-adr
0 value wav-data-adr

: .wav-cc  ( cc -- )
   case
          0  of  ." unknown"           endof
          1  of  ." PCM"               endof
          2  of  ." MS ADPCM"          endof
          6  of  ." ITU G.711 a-law"   endof
          7  of  ." ITU G.711 au-law"  endof
      h# 11  of  ." IMA ADPCM"         endof
      h# 16  of  ." ITU G.723 ADPCM"   endof
      h# 31  of  ." GSM 6.10"          endof
      h# 40  of  ." ITU G.721 ADPCM"   endof
      h# 50  of  ." MPEG"              endof
      ( default )  ." unknown code: " dup u.
   endcase
;

: find-wav-chunk?  ( in chunk$ -- in' true | false )
   rot dup 4 + le-l@ over + swap h# c + ( chunk$ in-end in' )
   begin  2dup u>  while                ( chunk$ in-end in )
      dup 4 pick 4 pick comp 0=  if     ( chunk$ in-end in )
         nip nip nip true exit          ( in true )
      then
      4 + dup le-l@ + 4 +               ( chunk$ in-end in' )
   repeat  4drop
   false
;

: wav-ok?  ( in -- ok? )
   dup " RIFF" comp  swap 8 + " WAVE" comp  or 0=
;

: parse-wav-ok?  ( in -- ok? )
   0 to wav-fmt-adr  0 to wav-fact-adr  0 to wav-data-adr
   dup wav-ok? 0=  if  drop false exit  then
   dup " fmt " find-wav-chunk?  if  to wav-fmt-adr  then
   dup " fact" find-wav-chunk?  if  to wav-fact-adr  then
   " data" find-wav-chunk?  if  8 + to wav-data-adr  then
   wav-fmt-adr 0= wav-data-adr 0= or not
;

: wav-cc        ( -- cc )        wav-fmt-adr  dup  if      8 + le-w@  then  ;
: wav-in-#ch    ( -- #ch )       wav-fmt-adr  dup  if  h#  a + le-w@  then  ;
: wav-#sample   ( -- #sample )   wav-fact-adr dup  if      8 + le-l@  then  ;
: wav-blk-size  ( -- blk-size )  wav-fmt-adr  dup  if  h# 14 + le-w@  then  ;

: set-sample-rate  ( -- )
   wav-fmt-adr ?dup  if  h# c + le-l@ " set-sample-rate" $call-audio  then
;

0 value out-move
: condense-pcm  ( adr -- )
   wav-in-#ch #output-ch - /w * to in-skip
   #output-ch /w * to out-move
   dup dup 4 - le-l@  bounds  ?do          ( out )
      i over out-move move                 ( out )
      out-move +                           ( out' )
   in-skip +loop  drop                     ( )
;
: expand-pcm  ( adr -- )
   #output-ch wav-in-#ch - /w * to out-skip
   wav-in-#ch /w * to out-move
   dup dup 4 - le-l@  bounds  swap out-move -  ( out in-begin in-end )
   begin  2dup u<  while                   ( out in-begin in )
      dup 3 pick out-move move             ( out in-begin in )
      out-move - rot out-move + -rot       ( out' in-begin in' )
      2 pick out-skip erase                ( out in-begin in )
      rot out-skip + -rot                  ( out' in-begin in )
   repeat  3drop                           ( )
;

: play-pcm-once  ( adr len -- )  " write" $call-audio drop " write-done" $call-audio  ;
: play-pcm-loop  ( adr len -- )
   ." Press a key to abort" cr
   begin  2dup play-pcm-once  key?  until  key drop  2drop
;
' play-pcm-once to (play-pcm)

: play-pcm  ( adr -- error? )
   wav-in-#ch 0=  if  drop true exit  then
   set-sample-rate
   wav-data-adr 4 - le-l@ to /pcm-output
   wav-in-#ch #output-ch =  if
      /pcm-output (play-pcm)                 \ Play straight from the source
   else
   /pcm-output wav-in-#ch / #output-ch * to /pcm-output
   #output-ch wav-in-#ch <  if
      dup condense-pcm                       \ Skip extra channel data
      /pcm-output (play-pcm)
   else
      dup expand-pcm                         \ Convert mono to stereo
      /pcm-output (play-pcm)
   then  then
   false
;

: play-ima-adpcm  ( adr -- error? )
   wav-fact-adr 0=  if  drop true exit  then
   set-sample-rate
   wav-#sample #output-ch * /w * to /pcm-output
   \ Because alloc-mem does not guarantee contiguous physical memory, use load-base area.
   loaded + pagesize round-up tuck          ( out in out )
   dup /pcm-output erase                    ( out in out )
   wav-#sample wav-in-#ch wav-blk-size      ( out in out #sample #ch blk-size )
   adpcm-decoder                            ( out )
   /pcm-output (play-pcm)                   ( )
   false                                    ( error? )
;

: (play-wav)  ( adr -- error? )
   parse-wav-ok?  not  if  ." Not a .wav file" cr true exit  then
   " /audio" open-dev ?dup 0=  if  ." Cannot open audio device" cr true exit  then
   to audio-ih
   wav-cc  case
          1  of  wav-data-adr play-pcm        endof
      h# 11  of  wav-data-adr play-ima-adpcm  endof
      ( default )  ." Cannot play .wav format type: " dup .wav-cc true swap cr
   endcase
   audio-ih close-dev
;

: ($play-wav)  ( file-str -- )
   boot-read
   load-base (play-wav)  abort" Error playing wav file"
;

: $play-wav  ( file-str -- )  ['] play-pcm-once to (play-pcm)  ($play-wav)  ;
: play-wav  ( "filename< >" -- )  safe-parse-word $play-wav  ;

: $play-wav-loop  ( file-str -- )
   ['] play-pcm-loop to (play-pcm)
   ($play-wav)
;
: play-wav-loop  ( "filename< >" -- )  safe-parse-word $play-wav-loop  ;

\ LICENSE_BEGIN
\ Copyright (c) 2006 FirmWorks
\ 
\ Permission is hereby granted, free of charge, to any person obtaining
\ a copy of this software and associated documentation files (the
\ "Software"), to deal in the Software without restriction, including
\ without limitation the rights to use, copy, modify, merge, publish,
\ distribute, sublicense, and/or sell copies of the Software, and to
\ permit persons to whom the Software is furnished to do so, subject to
\ the following conditions:
\ 
\ The above copyright notice and this permission notice shall be
\ included in all copies or substantial portions of the Software.
\ 
\ THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
\ EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
\ MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
\ NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
\ LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
\ OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
\ WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
\
\ LICENSE_END
