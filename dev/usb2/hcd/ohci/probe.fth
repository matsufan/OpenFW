purpose: OHCI USB Controller probe
\ See license at end of file

hex
headers

: enable-root-hub-port  ( port -- )
   >r
   h# 1.0002 r@ hc-rh-psta!		\ enable port
   10 r@ hc-rh-psta!			\ reset port
   r@ d# 10 0  do
      d# 10 ms
      dup hc-rh-psta@ 10.0000 and  ?leave
   loop  drop
   r@ hc-rh-psta@ 10.0000 and 0=  if  abort  then
   h# 1f.0000 r> hc-rh-psta!		\ clear status change bits
   100 ms
;

: probe-root-hub-port  ( port -- )
   dup hc-rh-psta@ 1 and 0=  if  drop exit  then	\ No device connected
   ok-to-add-device? 0=  if  drop exit  then		\ Can't add another device

   dup enable-root-hub-port		( port )
   new-address				( port dev )
   over hc-rh-psta@ 200 and  if  speed-low  else  speed-full  then over di-speed!

   0 set-target				( port dev )	\ Address it as device 0
   dup set-address  if  2drop exit  then ( port dev )	\ Assign it usb addr dev
   dup set-target			( port dev )	\ Address it as device dev
   make-device-node			( )
;

false value ports-powered?

external
\ This version powers all the ports at once
: power-usb-ports  ( -- )
   hc-rh-desa@  dup h# 200  and  0=  if
      \ ports are power switched
      hc-rh-stat@ h# 1.0000 or hc-rh-stat!	\ power all ports
      hc-rh-desb@ d# 17 >> over h# ff and 0  ?do
         dup 1 i << and  if
            i hc-rh-psta@  h# 100 or i hc-rh-psta!	\ power port
         then
      loop  drop
   then  drop
   potpgt 2* ms			\ Wait until powergood
   true to ports-powered?
;

\ This version assumes that power has been applied already, and
\ all we have to do is wait enough time for the devices to be ready.
: wait-after-power  ( target-msecs -- )
   ports-powered?  if  drop exit  then  ( target-msecs )
   begin  dup get-msecs - 0<=  until    ( target-msecs )
   drop                                 ( )
   true to ports-powered?
;

\ This version powers the ports in a staggered fashion to reduce surge current
: stagger-power  ( -- )
   hc-rh-desa@  h# 200 and  0=  if               ( )
      hc-rh-desa@ h# 100 or hc-rh-desa!	\ Individual power switching mode
      hc-rh-desa@ h# ff and  h# f min            ( numports )
      1 over lshift 1-                           ( numports bitmask )
      d# 17 lshift  hc-rh-desb@ or  hc-rh-desb!  ( numports )
      0  ?do                                     ( )
         i hc-rh-psta@  h# 100 or i hc-rh-psta!	 ( )  \ power port
         d# 10 ms            \ Stagger to lower surge current
      loop                                       ( )
   then
   potpgt 2* ms			\ Wait until powergood
   true to ports-powered?
;

: probe-usb  ( -- )
   \ Power on ports
   ports-powered? not  if  power-usb-ports  then

   \ Setup PowerOnToPowerGoodTime and OverCurrentProtectionMode
   hc-rh-desA@  dup h# 00ff.ffff and
   h# 800 or potpgt d# 24 << or  hc-rh-desA!	\ per-port over-current status

   \ Probe each port
   alloc-pkt-buf
   h# ff and  0  ?do
      i ['] probe-root-hub-port catch  if
         drop ." Failed to probe root port " i u. cr
      then
      3.0000 i hc-rh-psta!			\ Clear change bits
   loop
   free-pkt-buf
;

: reprobe-usb  ( xt -- )
   alloc-pkt-buf
   hc-rh-desA@ h# ff and 0  ?do
      i hc-rh-psta@ 3.0000 and  if
         i over execute				\ Remove obsolete device nodes
         i ['] probe-root-hub-port catch  if
	    drop ." Failed to probe root port " i u. cr
         then
         3.0000 i hc-rh-psta!			\ Clear change bits
      then
   loop  drop
   free-pkt-buf
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
