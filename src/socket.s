.equ STDOUT_FILENO, 1

.equ SYS_WRITE, 64
.equ SYS_EXIT, 93
.equ SYS_SOCKET, 198

.equ AF_INET6, 10
.equ SOCK_STREAM, 1

.section .rodata

msg_socket_ok:
    .ascii "Socket created successfully!\n"
msg_socket_ok_len = . - msg_socket_ok

msg_socket_err:
    .ascii "Failed to create socket.\n"
msg_socket_err_len = . - msg_socket_err

.section .text
.global _start

_start:
    # socket(AF_INET6, SOCK_STREAM, 0)
    mov x0, #AF_INET6
    mov x1, #SOCK_STREAM
    mov x2, #0
    mov x8, #SYS_SOCKET
    svc #0

    # check if the socket creation succeeded (fd >= 0)
    cmp x0, #0
    b.lt socket_error

    # save the socket file descriptor
    mov x19, x0

    # print the success message
    mov x0, #STDOUT_FILENO
    adr x1, msg_socket_ok
    mov x2, #msg_socket_ok_len
    mov x8, #SYS_WRITE
    svc #0
    b exit_ok

socket_error:
    mov x0, #STDOUT_FILENO
    adr x1, msg_socket_err
    mov x2, #msg_socket_err_len
    mov x8, #SYS_WRITE
    svc #0
    b exit_err

exit_ok:
    mov x0, #0
    mov x8, #SYS_EXIT
    svc #0

exit_err:
    mov x0, #1
    mov x8, #SYS_EXIT
    svc #0
