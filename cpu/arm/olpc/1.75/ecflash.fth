\ See license at end of file
purpose: Reflash the EC code

0 value ec-ih
: open-ec  ( -- )
   ec-ih 0=  if
      " /eccmd" open-dev to ec-ih
   then
   ec-ih 0= abort" Can't open eccmd node"
;
: close-ec  ( -- )
   ec-ih  if
      ec-ih close-dev
      0 to ec-ih
   then
;

h# 10000 value /ec-flash

char 3 value expected-ec-version

: check-signature  ( adr -- )
   h# ff00 +                   ( adr' )
   dup  " XO-EC" comp abort" Bad signature in EC image"  ( adr )
   dup ." EC firmware verison: " cscount type cr         ( adr )
   dup 6 + c@ expected-ec-version <>  abort" Wrong EC version"  ( adr )
   drop
;
: ?ec-image-valid  ( adr len -- )
   dup /ec-flash <>  abort" Image file is the wrong size"   ( adr len )
   over c@ h# 02 <>  abort" Invalid EC image - must start with 02"
   2dup 0 -rot  bounds ?do  i l@ +  /l +loop    ( adr len checksum )
   abort" Incorrect EC image checksum"          ( adr len )
   over check-signature                         ( adr len )
   2drop
;

0 value ec-file-loaded?
: get-ec-file  ( "name" -- )
   safe-parse-word  ." Reading " 2dup type cr
   $read-open
   load-base /ec-flash  ifd @ fgets  ( len )
   ifd @ fclose                      ( len )
   load-base swap ?ec-image-valid
;
: flash-ec  ( "filename" -- )
   get-ec-file
   open-ec
   " enter-updater" ec-ih $call-method
   ." Erasing ..." " erase-flash" ec-ih $call-method cr
   ." Writing ..." load-base /ec-flash 0 " write-flash" ec-ih $call-method  cr
   ." Verifying ..."
   load-base /ec-flash + /ec-flash 0 " read-flash" ec-ih $call-method
   load-base  load-base /ec-flash +  /ec-flash  comp
   abort" Miscompare!"
   cr
   " reboot-ec" ec-ih $call-method
   close-ec
;
: read-ec-flash  ( -- )
   open-ec
   " enter-updater" ec-ih $call-method
   flash-buf /ec-flash 0 " read-flash" ec-ih $call-method
\  " reboot-ec" ec-ih $call-method
   close-ec
;
: save-ec-flash  ( "name" -- )
   safe-parse-word $new-file
   read-ec-flash
   load-base /ec-flash ofd @ fputs
   ofd @ fclose
;

\ LICENSE_BEGIN
\ Copyright (c) 2010 FirmWorks
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