\ See license at end of file
purpose: Driver for "EC" (KB3700) chip

\ EC access primitives

h# 380 constant iobase

: ec@  ( index -- b )  wbsplit iobase 1+ pc!  iobase 2+ pc!  iobase 3 + pc@  ;
: ec!  ( b index -- )  wbsplit iobase 1+ pc!  iobase 2+ pc!  iobase 3 + pc!  ;

\ Write a word to an EC index.
: ecw! ( wdata index )
   wbsplit           ( wdata index_lsb index_msb ) 
   iobase 1+ pc!        ( wdata index_lsb )
   dup iobase 2+ pc!    ( wdata index_lsb )
   swap wbsplit      ( index_lsb wdata_lsb wdata_msb )
   iobase 3 + pc!        ( index_lsb wdata_lsb )
   swap 1 +          ( wdata_lsb index_lsb+1 ) 
   iobase 2+ pc!        ( wdata_lsb )
   iobase 3 + pc!
;

\ Read a word from an EC index
: ecw@ ( index -- data )
   dup ec@ 8 << swap             ( msb index )
   1+ ec@ or                     ( data )
;

: kbc-debug-on    ( -- )         1 fbfe ec! ;
: kbc-debug-off   ( -- )         0 fbfe ec! ;

: kbc-regs
   ." KBCCB: "
   fc80 ec@ dup . cr
   dup 20 and ."   Aux " if ." Dis" else ." Enb" then cr
       10 and ."   Kbc " if ." Dis" else ." Enb" then cr
   ." KBCIF: " 
   fc82 ec@ dup . cr
   dup 2 and if ."   OBF" cr then 
       1 and if ."   IBF" cr then 
   ." KBSTS: " 
   fc86 ec@ dup . cr
   dup 2 and if ."   IBF" cr then 
       1 and if ."   OBF" cr then 
   ." PS2PF: "
   fee1 ec@ dup . cr
   dup 8 and if ."   Perr" cr then 
   dup 4 and if ."   TxOut" cr then 
   dup 2 and if ."   TxD" cr then 
       1 and if ."   RxD" cr then 
   fee2 ec@
   ." PS2CTRL: " . cr
   f501 ec@
   ." SrvPS2: " . cr
   64 pc@ 
   ."     p64: " . cr
   60 pc@ 
   ."     p60: " . cr
  
;

: ec-dump  ( offset len -- )
   ." Addr   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f" cr  cr
   push-hex
   bounds  ?do
      i 4 u.r space
      i h# 10 bounds  do  i ec@ 3 u.r  loop  cr
      exit? ?leave
   h# 10 +loop
   pop-base
;

\ EC internal addresses

: wait-ib-empty  ( -- )
   d# 1000 0  do  h# 6c pc@  2 and  0=  if  unloop exit  then  1 ms  loop
   true abort" EC port 6c input buffer timeout"
;
: ec-cmd-out  ( cmd -- )  wait-ib-empty  h# 6c pc!  ;
: ec-wb  (  -- )  wait-ib-empty  h# 68 pc!  ;
: ec-rb  ( -- b )
   d# 200 0  do
      h# 6c pc@  3 and  1 =  if
         h# 68 pc@
         unloop exit
      then
      1 ms
   loop
   true abort" EC port 6c output buffer timeout"
;

: ec-cmd66  ( byte -- )
   h# 66  pc! 
   \ It typically requires about 200 polls
   d# 4000 0  do  1 ms  h# 66 pc@ 2 and 0=  if  unloop exit  then  loop
   true abort" EC didn't respond to port 66 command"
;

: ec-rw    ( -- w )  ec-rb ec-rb swap bwjoin  ;
: ec-ww    ( -- w )  wbsplit ec-wb ec-wb  ;
: ec-wl    ( -- l )  lbsplit ec-wb ec-wb ec-wb ec-wb ;

: (ec-cmd-b!)  ( b cmd -- )  ec-cmd-out  ec-wb  ;
: (ec-cmd-w!)  ( b cmd -- )  ec-cmd-out  ec-ww  ;
: (ec-cmd-l!)  ( l cmd -- )  ec-cmd-out  ec-wl  ;
: (ec-cmd-b@)  ( cmd -- b )  ec-cmd-out  ec-rb  ;
: (ec-cmd-w@)  ( cmd -- w )  ec-cmd-out  ec-rw  ;

: too-many-retries  ( -- )  true abort" Too many EC command retries"  ;
d# 10 constant #ec-retries

: ec-cmd     ( cmd -- )
   #ec-retries  0  do                   ( cmd )
      dup ['] ec-cmd-out catch  0=  if  ( cmd )
         drop unloop exit
      then                              ( cmd x )
      drop                              ( cmd )
   loop                                 ( cmd )
   too-many-retries
;

\ Hideous retries to work around race conditions in the EC code
: ec-cmd-b!  ( b cmd -- )
   #ec-retries  0  do                      ( b cmd )
      2dup  ['] (ec-cmd-b!) catch  0=  if  ( b cmd )
         2drop unloop exit
      then                                 ( b cmd x x )
      2drop                                ( b cmd )
   loop                                    ( b cmd )
   too-many-retries
;

: ec-cmd-w!  ( w cmd -- )
   #ec-retries  0  do                      ( b cmd )
      2dup  ['] (ec-cmd-w!) catch  0=  if  ( b cmd )
         2drop unloop exit
      then                                 ( b cmd x x )
      2drop                                ( b cmd )
   loop                                    ( b cmd )
   too-many-retries
;


: ec-cmd-l!  ( l cmd -- )
   #ec-retries  0  do                      ( b cmd )
      2dup  ['] (ec-cmd-l!) catch  0=  if  ( b cmd )
         2drop unloop exit
      then                                 ( b cmd x x )
      2drop                                ( b cmd )
   loop                                    ( b cmd )
   too-many-retries
;

: ec-cmd-b@  ( cmd -- b )
   #ec-retries  0  do                      ( cmd )
      dup  ['] (ec-cmd-b@) catch  0=  if   ( cmd b )
         nip unloop exit
      then                                 ( cmd x )
      drop                                 ( cmd )
   loop                                    ( cmd )
   too-many-retries
;
: ec-cmd-w@  ( cmd -- w )
   #ec-retries  0  do                      ( cmd )
      dup  ['] (ec-cmd-w@) catch  0=  if   ( cmd w )
         nip unloop exit
      then                                 ( cmd x )
      drop                                 ( cmd )
   loop                                    ( cmd )
   too-many-retries
;

fload ${BP}/dev/olpc/kb3700/eccmdcom.fth

\ Commands that are specific to XO-1 and XO-1.5
: write-protect-fw ( -- )  3 ec-cmd  ;
: sci-queue@       ( -- b )  h# 84 ec-cmd-b@  ;

: (bat-gauge-id@)  ( -- sn0 .. sn7 )  h# 17 ec-cmd-out  8 0  do ec-rb  loop  ;
: bat-gauge-id@  ( -- sn0 .. sn7 )
   #ec-retries  0  do
      ['] (bat-gauge-id@) catch  0=  if  unloop exit  then
   loop
   too-many-retries
;
: board-id@      ( -- b )  h# 19 ec-cmd-b@  ;
: sci-source@    ( -- b )  h# 1a ec-cmd-b@  ;
: sci-mask!      ( b -- )  h# 1b ec-cmd-b!  ;
: sci-mask@      ( -- b )  h# 1c ec-cmd-b@  ;
: game-key@      ( -- w )  h# 1d ec-cmd-w@  ;
: (ec-date!)     ( day month year -- )  h# 1e ec-cmd-out  ec-wb ec-wb ec-wb  ;
: ec-date!       ( day month year -- )
   #ec-retries  0  do    ( d m y )
      3dup ['] (ec-date!) catch  0=  if  3drop unloop exit  then  ( d m y x x x )
      3drop              ( d m y )
   loop                  ( d m y )
   too-many-retries
;

: bat-init-nimh-gp     ( -- )  h# 20 ec-cmd  ;
: bat-init-lifepo4-byd ( -- )  h# 21 ec-cmd  ;
: bat-init-lifepo4-gp  ( -- )  h# 22 ec-cmd  ;
\ EC cmd 23 never worked right and has been deprecated
\ : wlan-off         ( -- )  0 h# 23 ec-cmd-b!  ;
\ : wlan-on          ( -- )  1 h# 23 ec-cmd-b!  ;
: wlan-wake        ( -- )  h# 24 ec-cmd  ;
: wlan-reset       ( -- )  h# 25 ec-cmd  ;
: dcon-power-off   ( -- )  0 h# 26 ec-cmd-b!  ;
: dcon-power-on    ( -- )  1 h# 26 ec-cmd-b!  ;
: reset-ec-warm    ( -- )  h# 27 ec-cmd  ;
: ebook-mode?      ( -- b )  h# 2a ec-cmd-b@  ;
: wlan-freeze      ( -- )  h# 35 ec-cmd  ;
: ec-wackup   ( ms -- ) lbsplit h# 36 ec-cmd-out ec-wb ec-wb ec-wb ec-wb ;


: (bat-gauge@)   ( -- b )  h# 18 ec-cmd-out  h# 31 ec-wb  ec-rb  ;  \ 31 is the EEPROM address
: bat-gauge@  ( -- b )
   #ec-retries  0  do
      ['] (bat-gauge@) catch  0=  if  unloop exit  then
   loop
   too-many-retries
;

: (bat-type@)    ( -- b )  h# 18 ec-cmd-out  h# 5f ec-wb  ec-rb  ;  \ 5f is the EEPROM address
: bat-type@  ( -- b )
   #ec-retries  0  do
      ['] (bat-type@) catch  0=  if  unloop exit  then
   loop
   too-many-retries
;

: autowack-delay   ( delay -- )   wbsplit f650 ec! f651 ec! ;

: ec-indexed-io-off  ( -- )  h# fe95 ec@  h# 40 invert and  h# fe95 ec!  ;

: sci-inhibit      ( -- )  h# 32 ec-cmd  ;
: sci-uninhibit    ( -- )  h# 34 ec-cmd  ;

0 [if]
\ EC mailbox access words

: ec-mb-adr@   ( -- w )  h# 80 ec-cmd-out  ec-rw  ;
: ec-mb-adr!   ( w -- )  h# 81 ec-cmd-out  ec-ww  ;
: ec-mb-setup  ( cmd w -- )  ec-mb-adr!  ec-cmd-out  ;

: ec-mb-b@    ( adr -- b )  h# 8a ec-mb-setup  h# 84 ec-cmd-b@  ;
: ec-mb-w@    ( adr -- w )  h# 88 ec-mb-setup  h# 82 ec-cmd-w@  ;
: ec-mb-b!    ( b adr -- )  h# 85 ec-mb-setup  ec-wb  h# 8b ec-cmd-out  ;
: ec-mb-w!    ( w adr -- )  h# 83 ec-mb-setup  ec-ww  h# 89 ec-cmd-out  ;
[then]

\ SCI source codes:
\ SCI_WAKEUP_EVENT             0x01   // Game button,
\ SCI_BATTERY_STATUS_CHANGE    0x02   // AC plugged/unplugged, ...
\    Battery inserted/remove, Battery Low, Battery full, Battery destroy
\ SCI_SOC_CHANGE               0x04   // SOC Change
\ SCI_ABNORMAL_EVENT           0x08
\ SCI_EB_MODE_CHANGE           0x10
\ SCI_WAKEUP_WLAN_EVENT        0x20

\ This command hard-resets the EC deeply enough for the SP write-protect to
\ be off when the system is powered up again.

: ec-reset  ( -- )  5  ec-cmd-b@ drop  ;

: kb3920?  ( -- flag )  h# 6c pc@ h# ff =  if  true exit  then   9 ec-cmd-b@ 9 =  ;

\ This makes the EC stop generating a flood of SCIs every time you do
\ the port 66 command sequence.
: sci-quiet  ( -- )  h# 50  h# ff03 ec!  ;


\ kbc-pause temporarily halts execution of the keyboard controller microcode.
\ kbc-resume makes it run again, picking up where it left off.
\ This is useful for accessing the SPI FLASH in cases where you do not
\ overwrite the keyboard controller microcodes.

: kbc-pause  ( -- )   h# dd ec-cmd66  ;
: kbc-resume  ( -- )  h# df ec-cmd66  ;

0 value kbc-off?

: kbc-on  ( -- )
   \ Release the reset line to the 8051 microcontroller in the EC,
   \ thus letting it restart with possibly-new microcode.
   h# ff14 ec@  1 invert and  h# ff14 ec!  \ Innocuous if already on

   false to kbc-off?
;

\ This restarts the EC and the CPU, resetting the EC state to its default.
\ EC indexed I/O will come up in enabled state.
: ec-reboot  ( -- )   h# db ec-cmd66  ;

\ This restarts only the host (no ec reset) but EC index I/O will come up 
\ in enable sate
: host-pwr-cycle ( -- ) h# d7 ec-cmd66 ;

: ec-ixio-reboot  ( -- )
   ['] ec-reboot catch  if
      ." Automatic restart failed.  Remove/reinstall the battery and AC." cr
      d# 10,000 ms
      power-off
   else
      begin again    \ Just wait for it to happen
   then
;

: ec-indexed-io-off?  ( -- flag )  h# ff14 ec@  h# ff =  ;
: ?ixio-restart  ( -- )
   ec-indexed-io-off?  if
      cr  red-letters
      ." Restarting to enable SPI FLASH writing.  Try again after the system restarts."
      black-letters cr
      d# 5000 ms
      ec-ixio-reboot
   then
;

\ While accessing the SPI FLASH, we have to turn off the keyboard controller,
\ because it continuously fetches from the SPI FLASH when it's on.  That
\ interferes with our accesses.

\ Unfortunately, since the system reset is mediated by the keyboard
\ controller, turning the keyboard controller back on resets the system.

: kbc-off  ( -- )
   kbc-off?  if  exit  then  \ Fast bail out
   ?ixio-restart
   h# d8 ec-cmd66      \ Prepare for reset
   h# ff14 ec@  1 or  h# ff14 ec!
   true to kbc-off?
;

: no-kbc-reboot  ( -- )  7 h# ff01 ec!  ;

: io-spi@  ( reg# -- b )  h# fea8 +  ec@  ;
: io-spi!  ( b reg# -- )  h# fea8 +  ec!  ;

\ We need the spi-cmd-wait because the data has to go out
\ serially on the SPI bus and that is a bit slower than
\ the IO port access.  We must wait to avoid overwriting
\ the command register during the serial tranfer.

: io-spi-out  ( b -- )  spicmd!  spi-cmd-wait  ;

: io-spi-reprogrammed  ( -- )
   ." Restarting..."  d# 2000 ms  cr
   kbc-on  begin again
;
: io-spi-reprogrammed-no-reboot  ( -- )
   no-kbc-reboot
   kbc-on
;

: io-spi-start  ( -- )
   ['] io-spi@    to spi@
   ['] io-spi!    to spi!
   ['] io-spi-out to spi-out
   use-ec-spi     \ spi-in, spi-cs-on, spi-cs-off via EC commands

   ['] io-spi-reprogrammed to spi-reprogrammed
   ['] io-spi-reprogrammed-no-reboot to spi-reprogrammed-no-reboot
   use-mem-flash-read
   [ifdef] uncache-flash  uncache-flash  [then]

   7 to spi-us   \ Measured time for "1 fea9 ec!" is 7.9 uS

   ignore-power-button  \ Guard against the user panicing
   disable-interrupts   \ Don't poll the EC
   kbc-off
;
: use-local-ec  ( -- )  ['] io-spi-start to spi-start  ;
use-local-ec

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
