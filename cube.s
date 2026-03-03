bits 16
org 0x7c00

start:
xchg bx, bx
xor ah, ah
mov al, 13h
int 10h ; setup 320 x 200 VGA
fninit ; init x87 FPU stack


xor ax, ax ; setup stack, 0000h(stack segment):7c00h(base pointer)
mov ss, ax
mov sp, 0x7c00
mov bp, sp


fld dword[zero] ; initial 0 push, doesn't matter if integer or float
sub sp, 32 ; 8 temporary spaces for variables:
; bp-4 : temp storage for x, y, z coordinates and perspective projection results
; bp-8 : Computed Z-coordinate
; bp-12 : Computed X-coordinate
; bp-16 : Computed y*sina
; bp-20 : Computed y*cosa, both for multiplication and dependency chain minimization
; bp-24 : integer cubescale*factor+z_offset converted to float to move the cube away from the camera
; bp-28 : integer cubescale converted to float, avoiding int to float conversion on both cases.
; bp-32 : yinc

mov dword [bp-24], cubescale*factor+z_offset
mov dword [bp-28], cubescale
fild word [bp-24]
fstp dword [bp-24]
fild word [bp-28]
fstp dword [bp-28]
fld dword [yinc]
fstp dword [bp-32]

mov ax, 0x1000
mov ds, ax ; set pixel buffer base address
mov ax, 0xA000
mov es, ax ; set VRAM base address


mov dx, cubescale ; y
mov bx, -cubescale ; x

db 0x0F, 0x1F, 0x00 ; NOP for instruction alignment
frame:
mov cx, 320*200
xor si, si
xor di, di
rep movsw
mov cx, 320*200
xor di, di
mov ax, 0x1000
mov es, ax
xor ax, ax
mov dx, cubescale ; reset y back to cubescal e

fadd dword [bp-32] ; add 0.05 to st0, which is the rotation angle in radians
fld st0 ; copy to avoid deletion of the rotation angle by fsincos
fsincos

; copy sina and cosa
fld st1
fld st1
; FPU stack: cosa sina cosa sina rotationangle

rep stosw ; cx = screen resolution, di = 0. clears the pixel buffer

fld dword [bp-28] ; load cubescale
fchs ; Z value is -cubescale, so change sign bit
fmul st1, st0
fmulp st2, st0
; pre-compute zcos and zsin
; FPU stack: zcosa zsina cosa sina rotationangle
mov al, 0x01 ; check the second face's rotation for backface culling
fld dword [zero]
fcomip st0, st2
jc skip2
mov al, 0x03
xor cx, 1 ; cx is a flag for the second face, if both faces are culled or none of them are culled, no need to swap x and z's sign bits.
skip2:
mov ah, 0x04 ; check the first face's rotation for backface culling
fld dword [zero]
fcomip st0, st1
jnc skip1
mov ah, 0x05
xor cx, 1
fchs
fxch st1
fchs
fxch st1
skip1:

yloop:
mov word [bp-4], dx ; move Y to temp storage
mov bx, -cubescale ; reset X value back to -cubescale, once it hits +cubescale(the limit)

fild word [bp-4] ; load Y to fpu stack and copy, both are used for ysina and ycosa respectively
fld st0

fmul st0, st5 ; ysina
fstp dword [bp-16]

fmul st0, st3 ; ycosa
fstp dword [bp-20]
; FPU stack : zcosa zsina cosa sina rotationangle
xloop:

fld st3
fld st3 ; cosa sina zcosa zsina cosa sina rotationangle

; compute xcosa xsina
mov word [bp-4], bx
fild word [bp-4]
fmul st1, st0
fmulp st2, st0

mov word [bp-4], dx ; load Y to temp storage for later use
; FPU stack : xcosa xsina zcosa zsina cosa sina rotationangle
fadd st0, st3 ; xcosa + zsina (x)
fst dword [bp-12] ; load rotated x value to stack
fxch st1 ; xsina | xcosa + zsina (x)
fsubr st0, st2
; zcos - xsin (z) || zsin + xcos (x)
fst dword [bp-8] ; load rotated z value to stack

fadd dword [bp-24] ; add z offset to the z value
fld1
fdivrp st1, st0 ; get reciprocal of z value
fild word [bp-4]
; y 1/z x
fxch st1
; 1/z y x

; perspective proj
fmul st1, st0
fmulp st2, st0
; y/z x/z

fld dword [bp-28]
fmul st1, st0
fmulp st2, st0
; y*50/z x*50/z
fchs
; flip Y coordinate for VGA write

mov di, 320
fistp word [bp-4]

imul di, word [bp-4] ; round(y*50/z) * 320

fistp word [bp-4] ; round(x*50/z)
fld dword [bp-8] ; load saved z value (-xsina + zcosa)
fld dword [bp-12] ; load saved x value (xcosa + zsina)
add di, 100*320+160 ; middle of the screen
add di, word [bp-4] ; round(x*50/z)

test cx, cx ; check if one, both, or no faces should be culled
; fpu stack : xcos + zsin || -xsin + zcos zcos zsin
jnz skipl
fchs
fxch st1
fchs
fxch st1
skipl:

; do the z-offset in the background for the second face(fpu stack is x z, but here x is treated as z and vice versa due to it being rotated 90 degrees in the Y axis)
fadd dword [bp-24]
fld1
fdivrp st1,st0
fchs
; -z because of -xsin90 x

mov word [bp-4], dx ; load Y for later use
mov byte [ds:di], ah ; plot first face's pixel


fild word [bp-4]
; y 1/z x
fxch st1
; 1/z y x
; perspective proj
fmul st1, st0
fmulp st2, st0
; y/z, x/z

; multiply by cubescale again
fld dword [bp-28]
fmul st1, st0
fmulp st2, st0

mov di, 320
fistp word [bp-4] ;round(y/z)

imul di, word [bp-4]

fistp word [bp-4]
add di, 100*320+160
add di, word [bp-4]

fld dword [bp-8]
; z zcos zsin rotationangle
fsub st0, st1  ; z = zcos - xsin, zcos - xsin - zcos = -xsin
fadd dword [bp-20] ; ycos - xsin due to 90 degree rotation, this is the Z value

; do the offset and reciprocal thing again
fadd dword [bp-24]
fld1
fdivrp st1,st0

mov dword [bp-4], cubescale ; initial z value with its sign bit changed due to -zsin90, this is the Y value due to rotation in X axis

mov byte [ds:di], al ; plot second face

fild word [bp-4] ; y 1/z


fld dword [bp-12]  ; xcos + zsin
fsub st0, st4 ;xcos + zsin - zsin = xcos
fadd dword [bp-16] ; xcos + ysin, this is the X value
; x y 1/z

fxch st2

; 1/z y x zcos zsin cos sin yinc
; perspective proj
fmul st1, st0
fmulp st2, st0
fld dword [bp-28]
fmul st1, st0
fmulp st2, st0
mov di, 320
fistp word [bp-4]
imul di, word [bp-4]


fistp word [bp-4]
add di, 100*320+160
add di, word [bp-4]

mov byte [ds:di], 0x02
add bx, 1 ; inc/dec = partial eflags modification, slower, so add and sub are used instead
cmp bx, cubescale
jle xloop
sub dx, 1
cmp dx, -cubescale
jge yloop
fcompp ; clear up fpu stack
mov ax, 0xA000 ; set es to vga memory
mov es, ax
fcompp ; clear up fpu stack
jmp frame


yinc dd 0.05
cubescale equ 50
factor equ 2
z_offset equ 25
zero:
times 510 - ($-$$) db 0
dw 0xAA55
