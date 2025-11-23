.equ STDOUT_FILENO, 1

.section .rodata

msg:
    .ascii "Hello from Drift on ARM64!\n"
msg_len = . - msg

.section .text

.global  _start
_start:
    # write(STDOUT_FILENO, msg, len)
    mov x0, #STDOUT_FILENO
    adr x1, msg
    mov x2, #msg_len
    mov x8, #64
    svc #0

    # exit(0)
    mov x0, #0
    mov x8, #93
    svc #0
