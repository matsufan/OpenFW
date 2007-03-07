purpose: USB boot keyboard keycode definitions
\ See license at end of file

hex
headers

\ The following keycodes maps keycodes to ASCII codes.  In those cases
\ where the keycode represents a key for which there is no ASCII equivalent,
\ the table contains a 0 byte.  This use of 0 does not prevent the generation
\ ASCII NUL (whose numerical value is 0) because control characters are
\ mostly generated by masking bits off of printable entries.  (The only
\ exceptions are Tab, BackSpace, Escape, and Return, which are the only
\ control characters that are directly generated by single keys on a
\ PC keyboard.)

\ "Syntactic sugar" to make keymaps a little easier to read and write
: xx  ( -- )  0 c,  ;

h# 68 constant /keysubmap
/keysubmap 2* 1+ constant /keymap

create keymap 2 c,	\ # of submaps
\ without shift key
( 00 )	xx          xx          xx          xx          ascii a c,  ascii b c,  ascii c c,  ascii d c,
( 08 )	ascii e c,  ascii f c,  ascii g c,  ascii h c,  ascii i c,  ascii j c,  ascii k c,  ascii l c,
( 10 )	ascii m c,  ascii n c,  ascii o c,  ascii p c,  ascii q c,  ascii r c,  ascii s c,  ascii t c,
( 18 )	ascii u c,  ascii v c,  ascii w c,  ascii x c,  ascii y c,  ascii z c,  ascii 1 c,  ascii 2 c,
( 20 )	ascii 3 c,  ascii 4 c,  ascii 5 c,  ascii 6 c,  ascii 7 c,  ascii 8 c,  ascii 9 c,  ascii 0 c,
( 28 )	0d c,       1b c,       08 c,       09 c,       20 c,       ascii - c,  ascii = c,  ascii [ c,
( 30 )	ascii ] c,  ascii \ c,  xx          ascii ; c,  ascii ' c,  ascii ` c,  ascii , c,  ascii . c,
( 38 )	ascii / c,  xx          xx          xx          xx          xx          xx          xx      
( 40 )	xx          xx          xx          xx          xx          xx          xx          xx      
( 48 )	xx          xx          xx          xx          7f c,       xx          0c c,       xx      
( 50 )	xx          xx          xx          xx          ascii / c,  ascii * c,  ascii - c,  ascii + c,
( 58 )	0d c,       ascii 1 c,  ascii 2 c,  ascii 3 c,  ascii 4 c,  ascii 5 c,  ascii 6 c,  ascii 7 c,
( 60 )	ascii 8 c,  ascii 9 c,  ascii 0 c,  ascii . c,  xx          xx          xx          ascii = c,
\ with shift key
( 00 )	xx          xx          xx          xx          ascii A c,  ascii B c,  ascii C c,  ascii D c,
( 08 )	ascii E c,  ascii F c,  ascii G c,  ascii H c,  ascii I c,  ascii J c,  ascii K c,  ascii L c,
( 10 )	ascii M c,  ascii N c,  ascii O c,  ascii P c,  ascii Q c,  ascii R c,  ascii S c,  ascii T c,
( 18 )	ascii U c,  ascii V c,  ascii W c,  ascii X c,  ascii Y c,  ascii Z c,  ascii ! c,  ascii @ c,
( 20 )	ascii # c,  ascii $ c,  ascii % c,  ascii ^ c,  ascii & c,  ascii * c,  ascii ( c,  ascii ) c,
( 28 )	0d c,       1b c,       08 c,       09 c,       20 c,       ascii _ c,  ascii + c,  ascii { c,
( 30 )	ascii } c,  ascii | c,  xx          ascii : c,  ascii " c,  ascii ~ c,  ascii < c,  ascii > c,
( 38 )	ascii ? c,  xx          xx          xx          xx          xx          xx          xx      
( 40 )	xx          xx          xx          xx          xx          xx          xx          xx      
( 48 )	xx          xx          xx          xx          7f c,       xx          0c c,       xx      
( 50 )	xx          xx          xx          xx          ascii / c,  ascii * c,  ascii - c,  ascii + c,
( 58 )	0d c,       xx          xx          xx          xx          ascii 5 c,  xx          xx        
( 60 )	xx          xx          xx          7f c,       xx          xx          xx          ascii = c,
		
\ The escape sequences implied by the following three tables are as
\ defined by the Windows NT "Portable Boot Loader" (formerly known
\ as ARC firmware) spec. They were subsequently adopted in some PowerPC
\ Open Firmware bindings.

create move-map  49 c,  52 c,
   ascii @ c,  \ Insert
   ascii H c,  \ Home
   ascii ? c,  \ Page Up
   ascii P c,  \ Delete  (use DEL, 7f)
   ascii K c,  \ End
   ascii / c,  \ Page Down
   ascii C c,  \ Right
   ascii D c,  \ Left
   ascii B c,  \ Down
   ascii A c,  \ Up

create func-map  3a c,  45 c,
   ascii P c,  \ F1
   ascii Q c,  \ F2
   ascii W c,  \ F3
   ascii x c,  \ F4
   ascii t c,  \ F5
   ascii u c,  \ F6
   ascii q c,  \ F7
   ascii r c,  \ F8
   ascii p c,  \ F9
   ascii M c,  \ F10
   ascii A c,  \ F11
   ascii B c,  \ F12

create keypad-map  h# 59 c,  h# 63 c,
   ascii K c,  \ 1/End
   ascii B c,  \ 2/Down
   ascii / c,  \ 3/PageDown
   ascii D c,  \ 4/Left
   ascii 5 c,  \ 5/<nothing>
   ascii C c,  \ 6/Right
   ascii H c,  \ 7/Home
   ascii A c,  \ 8/Up
   ascii ? c,  \ 9/PageUp
   ascii @ c,  \ 0/Insert
   ascii P c,  \ ./Del

: map?  ( scancode map-adr -- scancode false | ascii true )
   >r
   dup  r@ c@  r@ 1+ c@  between  if      ( scancode )
      r@ c@ -  r> 2+ + c@  true           ( char true )
   else                                   ( scancode )
      r> drop false
   then
;

\ Searascii for a matascii for "byte" in the "key" position of the table at
\ "table-adr". If a match is found, return the corresponding "value" byte
\ and true.  Otherwise return the argument byte and false.  The table
\ consists of pairs of bytes - the first byte of the pair is "key" and
\ the second is "value".  The end of the table is marked by a 0 byte in
\ the "key" position.
: translate-byte ( byte table-adr -- byte false | byte' true )
   begin  dup c@  while                             ( char adr )
      2dup c@ =  if  nip 1+ c@ true  exit  then     ( char adr )
      2+                                            ( char adr' )
   repeat                                           ( char adr' )
   drop false
;

: >keycode  ( scan-code -- char )
   keymap c@ 2 >  alt-gr?  and  if
      /keysubmap 2* +
   else
      shift?  if  /keysubmap +  then
   then
   keymap 1+ +  c@
;

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
