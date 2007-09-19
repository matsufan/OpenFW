purpose: OLPC secure boot
\ See license at end of file

\ Specs at http://wiki.laptop.org/go/Firmware_Security

: developer-device-list  " disk sd nand"   ;
: boot-device-list  " disk sd nand"   ;

true value debug-security?
: ?lease-debug   ( msg$ -- )
   debug-security?  if  type  else  2drop  then
;
: ?lease-debug-cr  ( msg$2 -- )
   debug-security?  if  type cr  else  2drop  then
;

: fail-load  ( -- )
   screen-ih stdout !
   ." OS Load Failed" cr
   quit
   begin again
;

h#  20 buffer: cn-buf  \ filename prefix - either "act" or "run"
h#  20 buffer: fn-buf  \ filename tail - either "os" or "rd"
h# 100 buffer: pn-buf  \ pathname - either "\boot" or "\boot-alt"
h# 100 buffer: dn-buf  \ device name

\ These macro definitions make it easy to compose device specifier strings
\ from the above name components.
also macros definitions
: FN  fn-buf count  ;
: CN  cn-buf count  ;
: DN  dn-buf count  ;
: PN  pn-buf count  ;
previous definitions

\ key: is a defining word whose children return key strings.
\ Each child word has the name of its key stored in the dictionary.
\ The first time that a child word executes, it uses the key name
\ to find the key value and caches the key value in RAM so subsequent
\ uses are faster.

: key:  ( name$ "name" -- key$ )
   create 0 , 0 ,  ",   \ adr len name
   does>   ( apf -- key$ )
   dup @  if  2@ exit  then   ( apf )
   dup 2 na+ count            ( apf name$ )
   2dup  find-drop-in  if     ( apf name$ key$ )
      2nip
   else                       ( apf name$ )
      ." Can't load key " type cr
      " Missing Key"          ( apf bad-key$ )
   then
   rot >r  2dup r> 2!         ( key$ )
;
" ospubkey"     key: oskey$
" fwpubkey"     key: fwkey$
" develpubkey"  key: develkey$
" leasepubkey"  key: leasekey$

\ pubkey$ is a global variable that points to the currently-selected
\ public key string.  It simplifies the stack manipulations for other
\ words, since the same key string is often used multiple times.
0 0 2value pubkey$

\ sig-buf is used for storing the binary version of signature strings
\ that have been decoded from the hex representation.

d# 256 constant /sig
/sig buffer: sig-buf

\ hex-decode decodes a hexadecimal signature string, storing it in
\ binary form at sig-buf.  It returns the adr,len of the binary string.

: hex-decode  ( hex$ -- true | sig$ false )
   dup /sig 2* <>  if
      ( ." Bad signature length" cr  )
      2drop true  exit
   then                         ( hex$ )
   sig-buf -rot                 ( adr hex$ )
   bounds ?do                   ( adr )
      i 2 push-hex $number pop-base  if  ( adr )
         2drop true unloop exit
      then                      ( adr n )
      over c!  1+               ( adr' )
   2 +loop                      ( adr )
   sig-buf tuck -   false       ( sig$ false )
;

\ parse-sig parses a "sig01:" format signature string, returning its
\ hashname and signature substrings.  It converts the signature
\ substring from ASCII hex to binary bytes.

: parse-sig  ( sig01$ -- true | hashname$ sig$ false )
   dup d# 89 <  if  2drop true exit  then
   bl left-parse-string  " sig01:" $=  0=  if  2drop true exit  then    ( rem$ )
   bl left-parse-string  dup d#  6 <>  if  4drop true exit  then  2swap ( hash$ rem$ )
   bl left-parse-string  nip d# 64 <>  if  4drop true exit  then        ( hash$ rem$ )
   newline left-parse-string  2swap nip  0<>  if  4drop true exit  then ( hash$ data$ )
   hex-decode  if  2drop true  else  false  then
;

\ zip-extent looks inside a memory-resident ZIP archive and returns
\ the address,length of a given component of that archive.  This
\ assumes that the components are "stored", not "deflated".  It
\ depends on the existence of a support package named "/lzip" to
\ do the work.

: zip-extent  ( name$ -- adr len )
   expand$  open-dev  ?dup 0=  if  " "  exit  then
   >r
   " offset" r@ $call-method load-base +
   " size" r@ $call-method drop
   r> close-dev
;

\ sig$ and img$ find the signature and signed-image components of
\ a ZIP bundle image that is already in memory.

: sig$  ( -- adr len )  " /lzip:\data.sig" zip-extent  ;
: img$  ( -- adr len )  " /lzip:\data.img" zip-extent  ;

\ bundle-name$ returns the full OFW pathname of a signed image
\ bundle, piecing it together from the device (DN), path (PN),
\ filename head (CN), and filename body (FN) macros.

: bundle-name$  ( -- $ )  " ${DN}:${PN}\${CN}${FN}.zip" expand$  ;

\ bundle-present? determines the existence (or not) of a signed image
\ bundle whose name is constructed from the current settings of the
\ device (DN), path (PN), filename head (CN), and filename body (FN).

: bundle-present?  ( -- flag )
   bundle-name$
   " Trying " ?lease-debug  2dup ?lease-debug-cr
   ['] (boot-read) catch  if  2drop false exit  then
   true
;

\ hashname remembers the most recently used hashname to guard against
\ attacks based on reuse of the same (presumably compromized) hash.

d# 32 buffer: hashname

\ valid? checks the validity of data$ against the ASCII signature
\ record sig01$, using the public key that pubkey$ points to.
\ It also verifies that the hashname contained in sig01$ is not
\ the same one that was last used (for verification of firmware
\ images against two different hashes).

: valid?  ( data$ sig01$ -- okay? )
   parse-sig  if
      ." Bad signature format in "  bundle-name$ type  cr
      false exit
   then                                     ( data$ hashname$ sig$ )

   2swap  d# 31 min                         ( data$ sig$ hashname$' )

   \ Check for duplicate hashname attacks
   2dup hashname count $=  if               ( data$ sig$ hashname$ )
      ." Duplicate hash name in "  bundle-name$ type  cr
      4drop false exit
   then                                     ( data$ sig$ hashname$ )

   hashname place                           ( data$ sig$ )

   pubkey$  hashname count  signature-bad? 0=        ( okay? )
;

\ earliest is the earliest acceptable date value (in seconds).
\ It is the date that the first test version of this code was
\ deployed.  If a laptop has any earlier date that than, that
\ date is presumed bogus.

d# 2007 d# 12 *  8 1- +  d# 31 *  d# 27 +  constant earliest

0. 2value current-seconds

\ get-date reads the date and time from the real time clock
\ and converts it to seconds.

\ The seconds conversion uses a simplified approach that ignores
\ leap years and the like - it assumes that all months are 31 days.
\ This is sufficient for comparison purposes so long as we use the
\ same calculation in all cases.  It is not good for doing
\ arithmetic on dates.
: get-date  ( -- error? )
   time&date           ( s m h d m y )
   d# 12 *  swap 1- +  ( s m h d m' )  \ Months start at 1
   d# 31 *  swap 1- +  ( s m h d' )    \ Days start at 1
   dup earliest  <  if  ( s m h d' )
      screen-ih stdout !
      ." The clock is not set properly" cr
      4drop true exit
   then        ( s m h d' )
   d# 24 * +   ( s m h' )
   d# 60 * +   ( s m' )   \ Can't overflow so far
   d# 60 um*   ( s d.s' )
   swap 0 d+   to current-seconds
   false
;

\ break$ splits a string into an initial substring of length n
\ (head$) and the residual substring (tail$).  If the input
\ string is shorter than n, head$ is the input string and tail$ is
\ the null string.

: break$  ( $ n -- tail$ head$ )
   2dup <  if  drop null$ 2swap exit  then
   dup >r  /string   ( tail$ )
   over r@ -  r>     ( tail$ head$ )
;

0. 2value exp-seconds  \ Accumulator for parsing data/time strings

\ numfield is a factor used for parsing 2-digit fields from date/time strings.
\ Radix is the number to scale the result by, i.e. one more than the maximum
\ value of the field.  Adjust is 0 for fields whose first valid value is 0
\ (hours, minutes, seconds) or 1 for fields that start at 1 (month,day).

: numfield  ( exp$ adjust radix -- exp$' )
   >r >r                      ( exp$ r: radix adjust )
   2 break$ $number  throw    ( exp$' num  r: radix adjust )
   r> -                       ( exp$  num' r: radix )
   dup r@ u>= throw           ( exp$  num  r: radix )

   \ No need to multiply the top half because it can only become nonzero
   \ on the last call to scale-time
   exp-seconds drop  r>  um*  ( exp$  num  d.seconds )
   rot 0  d+  to exp-seconds  ( exp$ )
;

\ expiration-to-seconds parses an expiration date string like
\ "20070820T130401Z", converting it to (double precision) seconds
\ according to the simplified calculation described above for "get-date"

: (expiration-to-seconds)  ( expiration$ -- true | d.seconds false )
   4 break$ $number throw          ( exp$' year )
   dup d# 2999 u> throw            ( exp$' year )
   0 to exp-seconds                ( exp$' )

   1 d# 12 numfield                ( exp$' )  \ Month
   1 d# 31 numfield                ( exp$' )  \ Day

   1 break$ " T" $=  0=  throw     ( exp$' )

   0 d# 24 numfield                ( exp$' )  \ Hour
   0 d# 60 numfield                ( exp$' )  \ Minute
   0 d# 60 numfield                ( exp$' )  \ Second

   " Z" $=  0=  throw              ( )
   exp-seconds
;

: expiration-to-seconds  ( expiration$ -- true | d.seconds false )
   push-decimal
   ['] (expiration-to-seconds)  catch  ( x x true  |  d.seconds false )
   pop-base
   dup  if  nip nip  then
;

\ expired? determines whether or not the expiration time string is
\ earlier than this machine's current time (from the real time clock).

: expired?  ( expiration$ -- bad? )
   expiration-to-seconds  if  true exit  then
   current-seconds  d<
;

d# 1024 constant /sec-line-max
/sec-line-max buffer: sec-line-buf

\ Remove bogus null characters from the end of mfg data tags (old machines
\ have malformed tags)
: ?-null  ( adr len -- adr' len' )
   dup  if
      2dup + 1- c@  0=  if  1-  then        ( adr len' )
   then
;

\ machine-id-buf is a buffer into which the machine signature string,
\ including serial number, UUID, and expiration time, is place.
\ That string is the signed object for lease and developer key verification.

d# 65 buffer: machine-id-buf

\ get-my-sn get the machine identification info including serial number
\ and UUID from the manufacturing data, placing it into machine-id-buf
\ for later use.  The expiration time is added later.

: get-my-sn  ( -- error? )

   " SN" find-tag  0=  if
      " No serial number in mfg data" ?lease-debug-cr
      true exit
   then                                             ( adr len )
   ?-null  dup d# 11 <>  if
      " Invalid serial number" ?lease-debug-cr
      2drop true exit
   then                                             ( adr len )
   machine-id-buf  swap  move

   [char] : machine-id-buf d# 11 + c!

   " U#" find-tag  0=  if
      " No UUID in mfg data" ?lease-debug-cr
      true exit
   then                                             ( adr len )
   ?-null  dup d# 36 <>  if
      " Invalid UUID" ?lease-debug-cr
      2drop true exit
   then                                             ( adr len )
   machine-id-buf d# 12 +  swap  move

   [char] : machine-id-buf d# 48 + c!

   false
;

\ my-sn$ returns the serial number portion of the machine identification.
\ get-my-sn must be called before my-sn$ will be valid.

: my-sn$  ( -- adr len )  machine-id-buf d# 11  ;


\ check-machine-signature verifies the signed object consisting
\ of the machine identification info (SN + UUID) plus the expiration
\ time "expiration$" against the crypto signature string sig$,
\ returning 1 if valid, -1 if invalid.  (The unusual return value
\ encoding is because the caller of check-machine-signature returns
\ a tree-state flag; see check-lease.)

: check-machine-signature  ( sig$ expiration$ -- -1|1 )
   0 hashname c!
   machine-id-buf d# 49 +  swap  move  ( sig$ )
   machine-id-buf d# 65  2swap  valid?  if  1  else  -1  then
;

\ check-lease checks a lease signature record in act01: format

\ -1 means lease is for this machine and is invalid
\  1 means lease is for this machine and is valid
\  0 means lease is not for this machine

: check-lease  ( act01-lease$ -- -1|0|1 )
   bl left-parse-string  " act01:"  $=  0=  if
      "   Not act01:" ?lease-debug-cr
      2drop -1 exit
   then
   bl left-parse-string                    ( rem$ serial$ )
   my-sn$ $=  0=  if                       ( rem$ )
      " is for a different system" ?lease-debug-cr
      2drop 0 exit
   then                                    ( rem$ )
   bl left-parse-string                    ( sig$ expiration$ )
   dup d# 16 <>  if                        ( sig$ expiration$ )
      " has bad expiration format" ?lease-debug-cr
      4drop -1 exit
   then                                    ( sig$ expiration$ )
   2dup expired?  if
      " expired" ?lease-debug-cr
      4drop -1 exit
   then                                    ( sig$ expiration$ )
   check-machine-signature                 ( -1|1 )

   dup 0<  if
      " has bad signature" ?lease-debug-cr
   else
      " valid" ?lease-debug-cr
   then
;

\ lease-valid? tries to read a lease file from the currently-selected
\ device, searches it for a lease record corresponding to this machine,
\ and checks that record for validity.  The return value is true if
\ a valid lease was found.

: lease-valid?  ( -- valid? )
   " ${DN}:\security\lease.sig" expand$            ( name$ )
   " Trying " ?lease-debug  2dup ?lease-debug-cr
   r/o open-file  if  drop false exit  then        ( ih )
   >r                                              ( r: ih )
   "   Lease " ?lease-debug                        ( r: ih )
   leasekey$ to pubkey$                            ( r: ih )
   begin
      sec-line-buf /sec-line-max r@ read-line  if  ( actual -eof? )
         2drop  r> close-file drop  false exit
      then                                         ( actual -eof? )
   while                                           ( actual )
      sec-line-buf swap check-lease  case          ( -1|0|1 )
          1  of  r> close-file drop  true exit   endof
         -1  of  r> close-file drop  false exit  endof
      endcase
   repeat         
   r> close-file drop  false
;

\ ?leased checks the currently-selected device for a valid lease
\ (see lease-valid?), setting the CN macro to "run" if one was
\ found or to "act" otherwise.  CN is used to construct a filename
\ like "runos.zip" (the normal OS, used when an valid lease is
\ present) or "actos.zip" (the activation version of the OS).

: ?leased  ( -- )
   lease-valid?  if  " run"  else " act"  then  cn-buf place
;

\ olpc-load-image is factor that is close the top level of the
\ secure boot process.  Given a directory prefix (e.g. "\boot")
\ and a space-delimited list of device names, it searches
\ each device in that list for an OS bundle in that directory.
\ The name of the OS bundle file is either "actos.zip" or
\ "runos.zip" according to whether or not a valid lease for
\ this machine is present on the same device.

: olpc-load-image  ( list$ dirname$ -- okay? )
   pn-buf place                             ( list$ )
   begin  dup  while                        ( list$ )
      bl left-parse-string                  ( list$ devname$ )
      dn-buf place                          ( list$' )
      ?leased                               ( list$ )
      bundle-present?  if                   ( list$ )
         "   OS found - " ?lease-debug
         0 hashname c!
         oskey$ to pubkey$
         img$  sig$  valid?  if
            "   Signature valid" ?lease-debug-cr
            img$ tuck load-base swap move  !load-size
            2drop true exit
         else
            "   Signature invalid" ?lease-debug-cr
         then
      then                                  ( list$ )
   repeat                                   ( list$ )
   2drop false
;

\ secure-load is the top level of the secure OS loading process.
\ It searches for lease files and signed OS image bundles on several
\ different devices.  If an OS bundle is not found, it then searches
\ the NAND FLASH for an alternate OS image.

: secure-load  ( -- okay? )
   load-crypto  if                          ( )
      ." Can't get crypto code" cr          ( )
      false exit
   then                                     ( )

   get-my-sn if  false exit  then
   get-date  if  false exit  then

   " os"  fn-buf place

   boot-device-list " \boot"      olpc-load-image  if  true exit  then
   " nand"          " \boot-alt"  olpc-load-image  if  true exit  then
   false
;

\ secure-load-ramdisk is called during the process of preparing an
\ OS image for execution.  It looks for an initrd bundle file on
\ the same device where the OS image was found, in a file named
\ either "runrd.zip" or "actrd.zip" depending on the presence of
\ a valid lease.

\ If no such bundle is found, the OS is booted without a ramdisk.
\ If a valid bundle is found, the OS is booted with that ramdisk.
\ If a bundle is found but it is not valid, the booting process aborts.

\ Call this after the kernel has already been moved away from load-base
\ We assume that pn-buf already has the path prefix string

: secure-load-ramdisk  ( -- )
\ Bad idea, because the cmdline would need to be signed too
\  " /lzip:\cmdline" zip-extent  to cmdline

   0 to /ramdisk

   ['] load-path behavior >r                      ( r: xt )
   ['] ramdisk-buf to load-path                   ( r: xt )

   " rd" fn-buf place
   bundle-present?  if
      r> to load-path

      "   RD found - " ?lease-debug
      0 hashname c!
      img$  sig$  valid?  if
         "   Signature valid" ?lease-debug-cr
         load-base to ramdisk-adr
         img$ dup to /ramdisk     ( adr len )
         load-base swap move      ( )
         exit
      else
         "   Signature invalid" ?lease-debug-cr
         fail-load
      then
   then
   r> to load-path
;


\ secure-boot performs the secure boot process

: secure-boot  ( -- )
   debug-security?  if  screen-ih stdout !  then
   ['] secure-load-ramdisk to load-ramdisk
   secure-load  0=  if  fail-load  then
   loaded sync-cache  " init-program" $find  if  execute  else  2drop  then
   go
;

\ wp? returns true if a "wp" manufacturing data tag is present

: wp?  ( -- flag )  " wp" find-tag  dup  if  nip nip  then  ;

\ ?secure-boot performs either the secure boot algorithm or the
\ historical boot algorithm depending on the presence of a "wp"
\ manufacturing data tag.

: ?secure-boot  ( -- )  wp?  if  secure-boot  else  boot  then  ;
" ?secure-boot" ' boot-command set-config-string-default


\ check-devel-key tests the developer signature string "dev01$".

\ -1 means the signature is for this machine and is invalid
\  1 means the signature is for this machine and is valid
\  0 means the signature is not for this machine

: check-devel-key  ( dev01$ -- -1|0|1 )
   bl left-parse-string  " dev01:"  $=  0=  if  2drop -1 exit  then  ( rem$ )
   bl left-parse-string                        ( rem$ serial$ )
   my-sn$ $=  0=  if  2drop 0 exit  then       ( rem$ )

   develkey$ to pubkey$
   " 00000000T000000Z"  check-machine-signature
;

\ has-developer-key? searches for a valid developer key on the
\ device given by the DN macro.

: has-developer-key?  ( -- flag )
   " ${DN}:\security\develop.sig" expand$    ( name$ )
   r/o open-file  if  drop false exit  then  ( ih )
   >r
   begin
      sec-line-buf /sec-line-max r@ read-line  if  ( actual -eof? )
         2drop  r> close-file drop  false exit
      then                                         ( actual -eof? )
   while                                           ( actual )
      sec-line-buf swap check-devel-key  case      ( -1|0|1 )
          1  of  r> close-file drop  true exit   endof
         -1  of  r> close-file drop  false exit  endof
      endcase
   repeat         
   r> close-file drop  false
;

\ developer?  searches a list of devices (given by "developer-device-list")
\ for a valid developer key

: developer?  ( -- flag )
   get-my-sn  if  false exit  then

   load-crypto  if                          ( )
      ." Can't get crypt code" cr           ( )
      false exit
   then                                     ( )

   developer-device-list                    ( list$ )
   begin  dup  while                        ( list$ )
      bl left-parse-string dn-buf place     ( list$' )
      has-developer-key?  if                ( list$' )
         2drop true  exit
      then                                  ( list$ )
   repeat                                   ( list$ )
   2drop false
;


fexit

Firmware security use cases:

a) load image signing:

Package: {run,act}{os,rd}.zip
Expiration: none
Signed object: OS or RD image file in .zip file
Signature: sha256_rsa256.sig in .zip file
Verification Algorithm: sha256 -> rsa256
Verification Key: OLPC-run-public-key

Rule: Don't run the image if the signature fails

b) Firmware update key

Package: /boot/bootfw.zip
Expiration: none (but should be versioned to avoid repeated updates)
Signed object: image in .zip file
Signature1: sha255.rsa in .zip file
Signature2: whirl.rsa in .zip file
Verification Algorithm: sha256 -> rsa256, whirlpool -> rsa256
Verification Key: OLPC-fw-public-key

Rule: If the developer key is valid, enter unlocked firmware state

c) Developer key

Package: /security/develop.key
Expiration: none
Signed object: <serial#>:<uuid>:00000000T000000Z (representing the machine)
Signature: rsa256 data in sig01 line
Verification Algorithm: rsa256
Verification Key: OLPC-devel-public-key

Rule: If the developer key is valid, enter unlocked firmware state

d) Activation lease

Package: /security/lease
Expiration: Yes - time on signature line
Signed object: <serial#>:<uuid>:<expiration time> (representing the machine)
Signature: rsa256 data in sig01 line
Verification Algorithm: rsa256
Verification Key: OLPC-act-public-key

Rule: If the lease is invalid, invoke act{os,rd}.zip instead of run{os,rd}.zip
