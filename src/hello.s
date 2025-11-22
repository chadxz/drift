.section .data

msg:
	.ascii "Hello from Drift on ARM64!\n"
msg_end:

	.section .text
	.global  _start

_start:
    # write(1, msg, len)
    mov x0, #1
    adr x1, msg
    sub x2, x1, x1
    add x2, x2, #(msg_end - msg)
    mov x8, #64
    svc #0

    mov x0, #0
    mov x8, #93
    svc #0
