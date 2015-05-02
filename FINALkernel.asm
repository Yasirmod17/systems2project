;;; ; ================================================================================================================================
;;; ; kernel.asm
;;; ; Conner Reilly / Tomal Hossain / Mohammed Ibrahim
;;; ;
;;; ; The kernel. Contains CREATE, EXIT, GET_ROM_COUNT, PRINT system calls. Creates a heap for the process table. See the documentation
;;; ; that accompanies this project for more.
;;; ;
;;; ; Revision 0 : Spring 2015
;;; ; ================================================================================================================================


;;; ; ================================================================================================================================
	.Code
;;; ; ================================================================================================================================



;;; ; ================================================================================================================================
;;; ; Entry point.


__start:

;;;  Find RAM.  Start the search at the beginning of the device table.
	COPY		%G0			*+_static_device_table_base

RAM_search_loop_top:

;;;  End the search with failure if we've reached the end of the table without finding RAM.
	BEQ		+RAM_search_failure	*%G0		*+_static_none_device_code

;;;  If this entry is RAM, then end the loop successfully.
	BEQ		+RAM_found		*%G0		*+_static_RAM_device_code

;;;  This entry is not RAM, so advance to the next entry.
	ADDUS		%G0			%G0		*+_static_dt_entry_size	; %G0 = &dt[RAM]
	JUMP		+RAM_search_loop_top

RAM_search_failure:

;;;  Record a code to indicate the error, and then halt.
	COPY		%G5		*+_static_kernel_error_RAM_not_found
	HALT

RAM_found:

;;;  RAM has been found.  If it is big enough, create a stack.
	ADDUS		%G1		%G0		*+_static_dt_base_offset ; %G1 = &RAM[base]
	COPY		%G1		*%G1 ; %G1 = RAM[base]
	ADDUS		%G2		%G0		*+_static_dt_limit_offset ; %G2 = &RAM[limit]
	COPY		%G2		*%G2 ; %G2 = RAM[limit]
	SUB		%G0		%G2		%G1 ; %G0 = |RAM|
	MULUS		%G4		*+_static_min_RAM_KB	 *+_static_bytes_per_KB ; %G4 = |min_RAM|
	BLT		+RAM_too_small	%G0		%G4
	MULUS		%G4		*+_static_kernel_KB_size *+_static_bytes_per_KB ; %G4 = |kmem|
	ADDUS		%SP		%G1		%G4 ; %SP = kernel[base] + |kmem| = kernel[limit]
	COPY		%FP		%SP		    ; Initialize %FP

;;;  Copy the RAM and kernel bases and limits to statically allocated spaces.
	COPY		*+_static_RAM_base		%G1
	COPY		*+_static_RAM_limit		%G2
	COPY		*+_static_kernel_base		%G1
	COPY		*+_static_kernel_limit		%SP

;;; Set the base of the trap table.
	SETTBR		+tt_base
	;; Set base of the interrupt buffer.
 	SETIBR		+IB_IP
	
;;; ; initialize the trap table entries to point to the appropriate interrupt handlers
	COPY 		*+BUS_ERROR 		+bus_err_int_handler
;;; ; it looks like right now on a CLOCK_ALARM, the simulator will vector to what I set for the PERMISSION_VIOLATION interrupt
	COPY 		*+PERMISSION_VIOLATION		+perm_int_handler
	COPY 		*+CLOCK_ALARM 			+clock_int_handler
	COPY 		*+SYSTEM_CALL 			+sysc_int_handler
	COPY 		*+INVALID_INSTRUCTION 		+invinst_int_handler
	
;;;	The kernel limit plus 1024 will become the base of the next program
	ADDUS *+_static_mem_base *+_static_kernel_limit	1024

	
;;;  With the stack initialized, call main() to begin booting proper.
	SUBUS		%SP		%SP		12 ; Push pFP / ra / rv
	COPY		*%SP		%FP		   ; pFP = %FP
	COPY		%FP		%SP		   ; Update FP.
	ADDUS		%G5		%FP		4  ; %G5 = &ra
	CALL		+_procedure_main		*%G5

;;;  We should never be here, but wrap it up properly.
	COPY		%FP		*%FP
	ADDUS		%SP		%SP		12 ; Pop pFP / args[0] / ra / rv
	COPY		%G5		*+_static_kernel_error_main_returned
	HALT

RAM_too_small:
;;;  Set an error code and halt.
	COPY		%G5		*+_static_kernel_error_small_RAM
	HALT
;;; ; ================================================================================================================================



;;; ; ================================================================================================================================
;;; ; Procedure: find_device
;;; ; Callee preserved registers:
;;; ;   [%FP - 4]:  G0
;;; ;   [%FP - 8]:  G1
;;; ;   [%FP - 12]: G2
;;; ;   [%FP - 16]: G4
;;; ; Parameters:
;;; ;   [%FP + 0]: The device type to find.
;;; ;   [%FP + 4]: The instance of the given device type to find (e.g., the 3rd ROM).
;;; ; Caller preserved registers:
;;; ;   [%FP + 8]:  FP
;;; ; Return address:
;;; ;   [%FP + 12]
;;; ; Return value:
;;; ;   [%FP + 16]: If found, a pointer to the correct device table entry; otherwise, null.
;;; ; Locals:
;;; ;   %G0: The device type to find (taken from parameter for convenience).
;;; ;   %G1: The instance of the given device type to find. (from parameter).
;;; ;   %G2: The current pointer into the device table.

_procedure_find_device:

;;;  Prologue: Preserve the registers used on the stack.
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G0
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G1
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G2
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G4

;;;  Initialize the locals.
	COPY		%G0		*%FP
	ADDUS		%G1		%FP		4
	COPY		%G1		*%G1
	COPY		%G2		*+_static_device_table_base

find_device_loop_top:

;;;  End the search with failure if we've reached the end of the table without finding the device.
	BEQ		+find_device_loop_failure	*%G2		*+_static_none_device_code

;;;  If this entry matches the device type we seek, then decrement the instance count.  If the instance count hits zero, then
;;;  the search ends successfully.
	BNEQ		+find_device_continue_loop	*%G2		%G0
	SUB		%G1				%G1		1
	BEQ		+find_device_loop_success	%G1		0

find_device_continue_loop:

;;;  Advance to the next entry.
	ADDUS		%G2			%G2		*+_static_dt_entry_size
	JUMP		+find_device_loop_top

find_device_loop_failure:

;;;  Set the return value to a null pointer.
	ADDUS		%G4			%FP		16 ; %G4 = &rv
	COPY		*%G4			0		   ; rv = null
	JUMP		+find_device_return

find_device_loop_success:

;;;  Set the return pointer into the device table that currently points to the given iteration of the given type.
	ADDUS		%G4			%FP		16 ; %G4 = &rv
	COPY		*%G4			%G2		   ; rv = &dt[<device>]
;;;  Fall through...

find_device_return:

;;;  Epilogue: Restore preserved registers, then return.
	COPY		%G4		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G2		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G1		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G0		*%SP
	ADDUS		%SP		%SP		4
	ADDUS		%G5		%FP		12 ; %G5 = &ra
	JUMP		*%G5

;;; ; ; ================================================================================================================================



;;; ; ; ================================================================================================================================
;;; ; ; Procedure: main
;;; ; ; Callee preserved registers:
;;; ; ;   [%FP - 4]: G0
;;; ; ;   [%FP - 8]: G3
;;; ; ;   [%FP - 12]: G4
;;; ; ; Parameters:
;;; ; ;   None
;;; ; ; Caller preserved registers:
;;; ; ;   [%FP + 0]: FP
;;; ; ; Return address:
;;; ; ;   [%FP + 4]:
;;; ; ; Return value:
;;; ; ;   <none>
;;; ; ; Locals:
;;; ; ;   None

	
_procedure_main:

	
;;; ; Callee Prologue: Push preserved registers.
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G0
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G3
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G4
	
;;; ;  If not yet initialized, set the console base/limit statics.
;;; 	        BNEQ            +print_init_loop        *+_static_console_base          0
	SUBUS           %SP             %SP             12 ; Push pfp / ra / rv
	COPY            *%SP            %FP                ; pFP = %FP
	SUBUS           %SP             %SP             4  ; Push arg[1]
	COPY            *%SP            3                  ; Find the 3rd device of the given type (i.e. the init.vmx ROM).
	SUBUS           %SP             %SP             4  ; Push arg[0]
	COPY            *%SP            *+_static_ROM_device_code ; Find a ROM device.
	COPY            %FP             %SP 		; Update %FP
	ADDUS           %G5             %SP             12 ; %G5 = &ra
	CALL            +_CREATE2         *%G5		   ; CREATE the init process
        ADDUS           %SP             %SP             8 ; Pop arg[0,1]
	COPY            %FP             *%SP	  	; %FP = pfp
	ADDUS           %SP             %SP             8 ; Pop pfp / ra
	COPY            %G4             *%SP              ; %G4 = &dt[init.vmx]
	ADDUS           %SP             %SP             4 ; Pop rv  
;;; ;  Panic if the 3rd ROM (init.vmx file) was not found.
;;; 	BNEQ            +main_found_3rd_ROM		%G4		0
;;; 	COPY            %G5             *+_static_kernel_error_ROM_not_found
;;; 	HALT
	
main_found_3rd_ROM:
;;; 	ADDUS		%G3		%G4		*+_static_dt_base_offset %G3 = &static 3rd ROM[base]
;;; 	COPY		*+_static_3rd_ROM_base		*%G3 ; Store static 3rd ROM[base]
;;; 	ADDUS		%G3		%G4		*+_static_dt_limit_offset ;%G3 = &static 3rd ROM[limit]
;;; 	COPY		*+_static_3rd_ROM_limit		*%G3 ; Store static 3rd ROM[limit]

	;; We'll use register %G0 to hold the base of process 3 (which we take from the process table)
	ADDUS		%G0		+_heap_process_table		4 ; Base of process 3, from the process table.
	ADDUS		%G3		+_heap_process_table		8 ; Limit of process 3, from the process table

	COPY		*+_current_user_process_id	3

 	SETBS		*%G0
 	SETLM		*%G3
	;;note that we don't want to set the alarm yet, because the init file will just immediately create all the processes.
	COPY		*+_static_kernel_int		0 ; we are no longer in the kernel.
	JUMPMD		0		0b110
	

	
;;; We should never reach this point for our project but - Epilogue: Pop and restore preserved registers, and then return
	

;;; ; ================================================================================================================================
;;; ; Procedure: print
;;; ; Callee preserved registers:
;;; ;   [%FP - 4]: G0
;;; ;   [%FP - 8]: G3
;;; ;   [%FP - 12]: G4
;;; ; Parameters:
;;; ;   [%FP + 0]: A pointer to the beginning of a null-terminated string.
;;; ; Caller preserved registers:
;;; ;   [%FP + 4]: FP
;;; ; Return address:
;;; ;   [%FP + 8]
;;; ; Return value:
;;; ;   <none>
;;; ; Locals:
;;; ;   %G0: Pointer to the current position in the string.

_procedure_print:

;;;  Prologue: Push preserved registers.
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G0
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G3
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G4

;;;  If not yet initialized, set the console base/limit statics.
	BNEQ		+print_init_loop	*+_static_console_base		0
	SUBUS		%SP		%SP		12 ; Push pfp / ra / rv
	COPY		*%SP		%FP		   ; pFP = %FP
	SUBUS		%SP		%SP		4  ; Push arg[1]
	COPY		*%SP		1		   ; Find the 1st device of the given type.
	SUBUS		%SP		%SP		4  ; Push arg[0]
	COPY		*%SP		*+_static_console_device_code ; Find a console device.
	COPY		%FP		%SP ; Update %FP
	ADDUS		%G5		%SP		12 ; %G5 = &ra
	CALL		+_procedure_find_device		*%G5
	ADDUS		%SP		%SP		8 ; Pop arg[0,1]
	COPY		%FP		*%SP		  ; %FP = pfp
	ADDUS		%SP		%SP		8 ; Pop pfp / ra
	COPY		%G4		*%SP		  ; %G4 = &dt[console]
	ADDUS		%SP		%SP		4 ; Pop rv

;;;  Panic if the console was not found.
	BNEQ		+print_found_console	%G4		0
	COPY		%G5		*+_static_kernel_error_console_not_found
	HALT
print_found_console:
	ADDUS		%G3		%G4		*+_static_dt_base_offset ; %G3 = &console[base]
	COPY		*+_static_console_base		*%G3 ; Store static console[base]
	ADDUS		%G3		%G4		*+_static_dt_limit_offset ; %G3 = &console[limit]
	COPY		*+_static_console_limit		*%G3 ; Store static console[limit]
	
print_init_loop:

;;;  Loop through the characters of the given string until the null character is found.
	COPY		%G0		*%FP ; %G0 = str_ptr
print_loop_top:
	COPYB		%G4		*%G0 ; %G4 = current_char

;;;  The loop should end if this is a null character
	BEQ		+print_loop_end	%G4		0

;;;  Scroll without copying the character if this is a newline.
	COPY		%G3		*+_static_newline_char ; %G3 = <newline>
	BEQ		+print_scroll_call	%G4	%G3

;;;  Assume that the cursor is in a valid location.  Copy the current character into it.
;;;  The cursor position c maps to buffer location: console[limit] - width + c
	SUBUS		%G3		*+_static_console_limit	*+_static_console_width	; %G3 = console[limit] - width
	ADDUS		%G3		%G3		*+_static_cursor_column	; %G3 = console[limit] - width + c
	COPYB		*%G3		%G4 ; &(height - 1, c) = current_char

;;;  Advance the cursor, scrolling if necessary.
	ADD		*+_static_cursor_column	*+_static_cursor_column		1 ; c = c + 1
	BLT		+print_scroll_end	*+_static_cursor_column	*+_static_console_width	; Skip scrolling if c < width
;;;  Fall through...

print_scroll_call:
	SUBUS		%SP		%SP		8 ; Push pfp / ra
	COPY		*%SP		%FP		  ; pfp = %FP
	COPY		%FP		%SP		  ; %FP = %SP
	ADDUS		%G5		%FP		4 ; %G5 = &ra
	CALL		+_procedure_scroll_console	*%G5
	COPY		%FP		*%SP ; %FP = pfp
	ADDUS		%SP		%SP		8 ; Pop pfp / ra

print_scroll_end:
;;;  Place the cursor character in its new position.
	SUBUS		%G3		*+_static_console_limit		*+_static_console_width ; %G3 = console[limit] - width
	ADDUS		%G3		%G3		*+_static_cursor_column	; %G3 = console[limit] - width + c
	COPY		%G4		*+_static_cursor_char ; %G4 = <cursor>
	COPYB		*%G3		%G4		      ; console@cursor = <cursor>

;;;  Iterate by advancing to the next character in the string.
	ADDUS		%G0		%G0		1
	JUMP		+print_loop_top

print_loop_end:
;;;  Epilogue: Pop and restore preserved registers, then return.
	COPY		%G4		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G3		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G0		*%SP
	ADDUS		%SP		%SP		4
	ADDUS		%G5		%FP		8 ; %G5 = &ra
	JUMP		*%G5
;;; ; ================================================================================================================================


;;; ; ================================================================================================================================
;;; ; Procedure: scroll_console
;;; ; Description: Scroll the console and reset the cursor at the 0th column.
;;; ; Callee reserved registers:
;;; ;   [%FP - 4]:  G0
;;; ;   [%FP - 8]:  G1
;;; ;   [%FP - 12]: G4
;;; ; Parameters:
;;; ;   <none>
;;; ; Caller preserved registers:
;;; ;   [%FP + 0]:  FP
;;; ; Return address:
;;; ;   [%FP + 4]
;;; ; Return value:
;;; ;   <none>
;;; ; Locals:
;;; ;   %G0:  The current destination address.
;;; ;   %G1:  The current source address.

_procedure_scroll_console:

;;;  Prologue: Push preserved registers.
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G0
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G1
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G4

;;;  Initialize locals.
	COPY		%G0		*+_static_console_base ; %G0 = console[base]
	ADDUS		%G1		%G0		*+_static_console_width	; %G1 = console[base] + width

;;;  Clear the cursor.
	SUBUS		%G4		*+_static_console_limit		*+_static_console_width ; %G4 = console[limit] - width
	ADDUS		%G4		%G4		*+_static_cursor_column	; %G4 = console[limit] - width + c
	COPYB		*%G4		*+_static_space_char ; Clear cursor.

;;;  Copy from the source to the destination.
;;;    %G3 = DMA portal
;;;    %G4 = DMA transfer length
	ADDUS		%G3		8		*+_static_device_table_base ; %G3 = &controller[limit]
	SUBUS		%G3		*%G3		12 ; %G3 = controller[limit] - 3*|word| = &DMA_portal
	SUBUS		%G4		*+_static_console_limit	%G0 ; %G4 = console[base] - console[limit] = |console|
	SUBUS		%G4		%G4		*+_static_console_width	; %G4 = |console| - width

;;;  Copy the source, destination, and length into the portal.  The last step triggers the DMA copy.
	COPY		*%G3		%G1 ; DMA[source] = console[base] + width
	ADDUS		%G3		%G3		4 ; %G3 = &DMA[destination]
	COPY		*%G3		%G0		  ; DMA[destination] = console[base]
	ADDUS		%G3		%G3		4 ; %G3 = &DMA[length]
	COPY		*%G3		%G4		  ; DMA[length] = |console| - width; DMA trigger

;;;  Perform a DMA transfer to blank the last line with spaces.
	SUBUS		%G3		%G3		8 ; %G3 = &DMA_portal
	COPY		*%G3		+_string_blank_line ; DMA[source] = &blank_line
	ADDUS		%G3		%G3		4   ; %G3 = &DMA[destination]
	SUBUS		*%G3		*+_static_console_limit	*+_static_console_width	; DMA[destination] = console[limit] - width
	ADDUS		%G3		%G3		4 ; %G3 = &DMA[length]
	COPY		*%G3		*+_static_console_width	; DMA[length] = width; DMA trigger

;;;  Reset the cursor position.
	COPY		*+_static_cursor_column		0 ; c = 0
	SUBUS		%G4		*+_static_console_limit		*+_static_console_width ; %G4 = console[limit] - width
	COPYB		*%G4		*+_static_cursor_char ; Set cursor.

;;;  Epilogue: Pop and restore preserved registers, then return.
	COPY		%G4		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G1		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G0		*%SP
	ADDUS		%SP		%SP		4
	ADDUS		%G5		%FP		4 ; %G5 = &ra
	JUMP		*%G5

;;; ; ================================================================================================================================


;;; ; ; ================================================================================================================================
;;; ; ; Procedure: GET_ROM_COUNT
;;; ; ; Callee preserved registers:
;;; ; ;   [%FP - 4]: G0
;;; ; ;   [%FP - 8]: G1
;;; ; ; Parameters:
;;; ; ;   None.
;;; ; ; Caller preserved registers:
;;; ; ;   [%FP+0]: FP
;;; ; ; Return address:
;;; ; ;   [%FP + 4]
;;; ; ; Return value:
;;; ; ;   [%FP + 8]
;;; ; ;   <number of ROMs>
;;; ; Locals:
;;; ;   %G0: The current pointer into the device table.
;;; ;   %G1: ROM count
	
GET_ROM_COUNT:

;;;  Prologue: Preserve the registers used on the stack.
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G0
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G1

;;;  Initialize the locals.
	COPY		%G0		*+_static_device_table_base 	; Initialize %G0 to point to beginning of device table.
	COPY		%G1		0 				; No ROMs found yet.

GET_ROM_COUNT_loop_top:

;;;  End the search if we've reached the end of the table without finding the device.
	BEQ		+GET_ROM_COUNT_loop_complete	*%G0		*+_static_none_device_code

;;;  If this entry matches the device type we seek, then increment the instance count.
	BNEQ		+GET_ROM_COUNT_continue_loop	*%G0		*+_static_ROM_device_code
	ADDUS		%G1				%G1		1

GET_ROM_COUNT_continue_loop:

;;;  Advance to the next entry.
	ADDUS		%G0			%G0		*+_static_dt_entry_size
	JUMP		+GET_ROM_COUNT_loop_top

GET_ROM_COUNT_loop_complete:

;;;  Set the return value to the ROM count.
	ADDUS		%G0			%FP		8 ; %G0 = &rv
	COPY		*%G0			%G1		   ; rv = ROM count
	
;;;  Epilogue: Restore preserved registers, then return.
	COPY		%G1		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G0		*%SP
	ADDUS		%SP		%SP		4
	ADDUS		%G5		%FP		4 ; %G5 = &ra

	JUMP		*%G5

;;; ; ; ================================================================================================================================

;;; ; ; ; ; ================================================================================================================================
;;; ; ; ; ; Procedure: _scheduler
;;; ; ; ; ; Callee preserved registers:
;;; ; ; ; ;   [%FP - 4]: G0
;;; ; ; ; ;   [%FP - 8]: G1
;;; ; ; ; ;   [%FP - 12]: G2
;;; ; ; ; ; Parameters:
;;; ; ; ; ;   [%FP + 0]: EXIT - this is a binary value. If it is 1, we are calling the scheduler from EXIT sysc, and thus we need to set the PID of the pro;;; ; ; ; ; 		cess that we want to exit to zero, and schedule the next process. Else, we just deschedule the current process and move to the next.
;;; ; ; ; ; Caller preserved registers:
;;; ; ; ; ;   [%FP + 4]: FP
;;; ; ; ; ; Return address:
;;; ; ; ; ;   [%FP + 8]
;;; ; ; ; ; Return value:
;;; ; ; ; ;   <none>
;;; ; ; ; ; Locals:
;;; ; ; ; ;   %G0: &start of process table
;;; ; ; ; ;   %G1: boolean exit
;;; ; ; ; ;   %G2: &end_of_process table
;;; ; ; ; ; ; ================================================================================================================================
	
_scheduler:
	;; Callee prologue. Preserve registers.
	SUBUS		%SP		%SP		4
	COPY 		*%SP		%G0	  	; preserve %G0 (note that preserved %G0 is [%SP+8])
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G1 		; preserve %G1
	SUBUS		%SP		%SP		4
	COPY		*%SP		%G2 		; preserve %G2

	;; First, since we will be restoring registers (we will be restoring %FP in particular, so we have no way of getting back to the return address), we need to put the return address in a static

	ADDUS		%G0		%FP		4

	COPY		*+_scheduler_return_address		*%G0
	
	;; Initialize locals

	;; %G0 is going to serve as an iterator through the process table
	COPY		%G0		+_heap_process_table
	;; %G1 will hold the value of the variable 'boolean exit'
	COPY		%G1		*%FP		
	;; %G2 is going to hold the value of the address of the end of the process table (so then we know to loop around if we are at the end of the pt)
	ADDUS		%G2		+_heap_process_table		*+_pt_length

	

	
;;; The first thing that we are going to want to do is find the process id of the current process in the process table
	BEQ		+_deschedule_current_process	*%G0		*+_current_user_process_id
	
;;; Iterate through the process table to find the entry we want.
seek_process_id_loop_top:	

	;; if we are not at the end of the process table, continue with the loop
	BNEQ		+seek_process_id_loop_continue		%G0			%G2
	;; if we are at the end of the process table, we want to go back to the beginning
	COPY		%G0		+_heap_process_table
	JUMP		+seek_process_id_loop_top

seek_process_id_loop_continue:	

	ADD		%G0					%G0		48
	BNEQ		+seek_process_id_loop_top		*%G0		*+_current_user_process_id
	
	
;;; Descheduler. Preserves the registers and the IP.
_deschedule_current_process:	

	;; if boolean exit is 1, we are exiting the current process and therefore want to set the process ID to zero
	BNEQ		+_pt_register_preserver		%G1		1
	COPY		*%G0			0 ; if we're terminating a process, set the pid to zero
	JUMP		+_next_pt_entry_loop_top

	;; if we are only descheduling a process and not exiting it, we want to preserve the registers of the process
_pt_register_preserver:	
	;; preserve the registers for the interrupted process
	ADD		%G0			%G0		44
	COPY	 	*%G0			*+fpTemp
	SUB		%G0			%G0		4
	COPY		*%G0			*+spTemp
	SUB		%G0			%G0		4
	COPY		*%G0			%G5
	SUB		%G0			%G0		4
	COPY		*%G0			%G4
	SUB		%G0			%G0		4
	COPY		*%G0			%G3
	;; %G3 has been preserved - now we will use it to preserve %G2, %G1, %G0
	SUB		%G0			%G0		4
	COPY 		*%G0			*%SP 					; *%SP holds the value of %G2
	SUB		%G0			%G0		4
	ADDUS		%G3			%SP		4
	COPY 		*%G0			*%G3 					; *[%SP+4] holds the value of %G1
	SUB		%G0			%G0		4
	ADDUS		%G3			%SP		8
	COPY		*%G0			*%G3					; *[%SP+8] holds the value of %G0
	SUB		%G0			%G0		4
	ADDUS		*%G0			*+IB_IP		16 			; preserve the IP + 16

	;; make sure %G0 is pointing to one of the process id entries
	ADDUS		%G0		%G0		36

;;; FIND THE NEXT NON-ZERO PROCESS ID (could be the one we are at now)
	
;;; Iterate through the process table to find the entry we want.
_next_pt_entry_loop_top:	

	;; if we are not at the end of the process table, continue with the loop
	BNEQ		+_next_pt_entry_loop_continue		%G0			%G2
	;; if we are at the end of the process table, we want to go back to the beginning
	COPY		%G0			+_heap_process_table
	JUMP		+_next_pt_entry_loop_top

_next_pt_entry_loop_continue:	

	BNEQ		+_schedule_next_process			*%G0		0
	ADD		%G0					%G0		48
	JUMP		+_next_pt_entry_loop_top
	
_schedule_next_process:
	COPY		*+_current_user_process_id		*%G0 ; set the current user process id to be the next scheduled process
	;; Restore registers for newly scheduled process
	ADD		%G0		%G0			44
 	COPY		%FP		*%G0
	SUB		%G0		%G0			4
 	COPY		%SP		*%G0
	SUB		%G0		%G0			4
	COPY		%G5		*%G0	
	SUB		%G0		%G0			4
	COPY		%G4		*%G0
	SUB		%G0		%G0			4
	COPY		%G3		*%G0
	SUB		%G0		%G0			4
	COPY		%G2		*%G0
	SUB		%G0		%G0			4
	COPY		%G1		*%G0
	SUB		%G0		%G0			4
	COPY		*+temp_G0	*%G0	;save G0 cos we'll need to refer to it for IP jump
	SUB		%G0		%G0			4
	COPY		*+IB_IP		*%G0
	
	SUB		%G0		%G0			4
	ADDUS		*%G0		*%G0			16 ; this is an ad hoc soln to a bug - we were setting the limit one instruction short (remember that right now our limit is literally the end of the programs text and statics...this is terrible, considering that it won't allow for a stack or heap in user programs, but we just want it all to work right now)
	SETLM		*%G0

	SUB		%G0		%G0			4
	SETBS		*%G0
	COPY		%G0		*+temp_G0

	COPY		*+_static_kernel_int		0 ; we're jumping out of the kernel
	SETALM		*+_clk_alm	1
	
	JUMPMD		*+IB_IP		0b110

	
	JUMP		*+_scheduler_return_address

	
	
;;; ; ; ; ================================================================================================================================
;;; ; ; ; Allocates space in the heap.
;;; ; ; ; Procedure: _heap_allocator
;;; ; ; ; Callee preserved registers:
;;; ; ; ;   [%FP - 4]: G0
;;; ; ; ;   [%FP - 8]: G1
;;; ; ; ; Parameters:
;;; ; ; ;   [%FP + 0]: size of memory chunk that we want to allocate
;;; ; ; ; Caller preserved registers:
;;; ; ; ;   [%FP + 4]: FP
;;; ; ; ; Return address:
;;; ; ; ;   [%FP + 8]
;;; ; ; ; Return value:
;;; ; ; ;   [%FP + 12]
;;; ; ; ;   <ptr to the base of the block we just allocated in the heap>
;;; ; ; ; Locals:
;;; ; ; ;   %G0: size of memory chunk to allocate
;;; ; ; ;   %G1: used to put rv on stack

;; How will we know if the heap is empty? *+_heap_top will have a value of zero
_heap_allocator:

;;;  Callee prologue.
	;;; ; ; Callee  Prologue: Preserve registers

	SUBUS           %SP             %SP             4
	COPY            *%SP            %G0
	SUBUS           %SP             %SP             4
	COPY		*%SP		%G1

	
;;; ; ; Initialize locals

	;; Locals whose values are taken from the stack. 
	COPY 		%G0		*%FP		  ; %G0 = size
	
	;; if the heap hasn't been initialized, initialize it.
	BNEQ		+_allocate		*+_heap_top		0

	
_initialize_heap:
	;; to give an indicator that the heap is not empty, we will set _heap_top to 1
	COPY		*+_heap_top 		0x1
	;; since we are initializing the heap, we will make _heap_next_free_block equal the next block (note that this is the process_table static rn)
	ADDUS		*+_heap_next_free_block		+_heap_next_free_block		0x4
	;; 
	
_allocate:
	;; All that we need to do is return the pointer to the next free block
	ADDUS		%G1		%FP		12 ; %G1 = &rv
	COPY		*%G1		*+_heap_next_free_block ; rv = &nextfreeblock
	
	;; now we need to increase _heap_next_free_block by the size of the memory chunk asked for
	ADDUS		*+_heap_next_free_block		*+_heap_next_free_block		%G0

	;; Callee epilogue: Restore registers and return
	COPY		%G1		*%SP
	ADDUS		%SP		%SP		4
	COPY		%G0		*%SP
	ADDUS		%SP		%SP		4

	
	JUMP		*%G5
	
;;; ; ================================================================================================================================


;;; ; ; ================================================================================================================================
;;; ; ; Procedure: _CREATE2 (it's called CREATE2 because there was a CREATE at some point, but it used a process table in the statics)
;;; ; ; Callee preserved registers:
;;; ; ;   [%FP - 4]: G0
;;; ; ;   [%FP - 8]: G3
;;; ; ;   [%FP - 12]: G4
;;; ; ; Parameters:
;;; ; ;   [%FP + 0]: The device type to find...note that this is unnecessary, since we have ROM device in a static. I'll remove this arg if I have the time.
;;; ; ;   [%FP + 4]: The instance of the given device type to find (e.g., the 3rd ROM).
;;; ; ; Caller preserved registers:
;;; ; ;   [%FP + 8]: FP
;;; ; ; Return address:
;;; ; ;   [%FP + 12]
;;; ; ; Return value:
;;; ; ;   <pointer to the base of the loaded process in RAM>
;;; ; ; Locals:
;;; ; ;   %G0: The ROM number that we want to load the process from.

_CREATE2:
;;; ; the kernel needs to know how many processes have been created, because the way that I am implementing right now is that I am just creating all processes, and then starting the round robin scheduling algo. The reason that I'm doing this is because if I havent created all processes, and I try to schedule the next process, we will loop through the process table potentially looking for a process that hasnt been created yet 

;;; ; Callee  Prologue: Preserve registers
	
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G0
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G3
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G4

;;; Initialize local
	ADDUS 		%G0		%FP		4
	COPY		%G0		*%G0

;;; Caller Prologue to find device:

	SUBUS           %SP             %SP             12 ; Push pfp / ra / rv
	COPY            *%SP            %FP                ; pFP = %FP
	SUBUS           %SP             %SP             4  ; Push arg[1]
	COPY            *%SP            %G0		   ; %G0 contains the instance of the ROM device we want to find
	SUBUS           %SP             %SP             4  ; Push arg[0]
	COPY            *%SP            *+_static_ROM_device_code    ; Find a ROM device.
	COPY            %FP             %SP ; Update %FP
	ADDUS           %G5             %SP             12 ; %G5 = &ra
	CALL            +_procedure_find_device         *%G5
	ADDUS           %SP             %SP             8 ; Pop arg[0,1]
	COPY            %FP             *%SP              ; %FP = pfp
	ADDUS           %SP             %SP             8 ; Pop pfp / ra
	COPY            %G4             *%SP              ; %G4 = &dt[nth ROM]
	ADDUS           %SP             %SP             4 ; Pop rv

;;; ;  Panic if the ROM was not found.
	BNEQ            +_CREATE2_found_ROM    %G4             0
	COPY            %G5             *+_static_kernel_error_ROM_not_found_see_CREATE2
	HALT

_CREATE2_found_ROM:
	ADDUS           %G3             %G4             *+_static_dt_base_offset	; %G3 = &nthROM[base]
	COPY            %G0		*%G3						; %G0 = ROM[base]
	ADDUS           %G3             %G4             *+_static_dt_limit_offset 	; %G3 = &nthROM[limit]
	COPY            %G3		*%G3						; %G3 = ROM[limit]
	
	COPY 		%G4	*+_static_mem_base					; store base of the first free chunk of memory in %G4

_CREATE2_copy_loop_top:
	
	COPY		*%G4	 	*%G0 						; copy the contents of the nth ROM into RAM, one word at a time
	ADD		%G0		%G0		4
	ADD 		%G4 		%G4 		4
	
	BEQ 		+_CREATE2_copy_loop_end 		%G0 		%G3 		; check to see if we have copied all contents from the ROM
	
	JUMP 		+_CREATE2_copy_loop_top

_CREATE2_copy_loop_end:


	;; DO NOT USE %G0 OR %G4 IN THE CALL TO _heap_allocator (%G4 holds RAM limit)

	;; We are now using %G0 to hold the return value from the _heap_allocator call
	
	;; The program has been copied into RAM. Now, we want to allocate a chunk of memory on the heap for the entry in the process table.

	;; Caller prologue to _heap_allocator
        SUBUS           %SP             %SP             12 				; Push pfp / ra / rv (rv is pointer to base of mem chunk)
	COPY            *%SP            %FP	   					; pFP = %FP
	SUBUS           %SP             %SP             4				; Push arg[0]
	COPY            *%SP            48			 			; arg[0] = size of process entry (48 bytes)
	COPY            %FP             %SP 						; Update %FP
	ADDUS           %G5             %SP             8 				; %G5 = &ra
	CALL            +_heap_allocator	         *%G5 				; CALL _heap_allocator
        ADDUS           %SP             %SP             4 				; Pop arg[0]
	COPY            %FP             *%SP	  					; %FP = pfp
	ADDUS           %SP             %SP             8 				; Pop pfp / ra
	COPY		%G0		*%SP 						; %G0 = ptr to base of mem chunk
	ADDUS           %SP             %SP             4 				; Pop rv


	;; We have the ptr to where we want to put the process entry in the heap in %G0. Now let's initialize the process entry


	
	;; Caller prologue to init_proc_entry
        SUBUS           %SP             %SP             8 				; Push pfp / ra (no return value)
	COPY            *%SP            %FP	   					; pFP = %FP
	SUBUS           %SP             %SP             4 				; Push arg[3]
	COPY            *%SP            %G0 		 				; arg[3] = &base_of_entry_in_process_table	
	SUBUS           %SP             %SP             4 				; Push arg[2]
	ADDUS           *%SP            %FP		4  				; arg[2] = &ROM instance number
	SUBUS           %SP             %SP             4				; Push arg[1]
	COPY            *%SP            %G4 						; arg[1] = RAM[limit] (limit = word after last word of prog)
	SUBUS           %SP             %SP             4				; Push arg[0]
	COPY            *%SP            *+_static_mem_base	 			; arg[0] = RAM[base]	
	COPY            %FP             %SP 						; Update %FP
	ADDUS           %G5             %SP             20 				; %G5 = &ra
	
	CALL            +_init2_proc_entry	         *%G5 				; CALL init_proc_entry
        ADDUS           %SP             %SP             16 				; Pop arg[0,1,2,3]
 	COPY            %FP             *%SP		  ; %FP = pfp
	ADDUS           %SP             %SP             8 				; Pop pfp / ra


;;; We're done with function calls, so we're in the callee epilogue phase of the process. First I'm going to place the return value, because I need to change "_static_mem_base"

	ADDUS		%G3		%FP		16
	COPY		*%G3		*+_static_mem_base

;;; Now, change the value of "static_mem_base" for the next process to be created.
	
	SUBUS		%G4		%G4		*+_static_mem_base		; %G4 = ROM[length]
	;; 	ADDUS		%G5		%FP		16 ; %G5 = &rv
	
	COPY		*%G5		*+_static_mem_base				; the return value will be the base of the program in main memory
	ADDUS 		*+_static_mem_base 		%G4		*+_static_mem_base	  ; get to limit of the program
	ADDUS 		*+_static_mem_base 		*+_static_mem_base 		1024 ; arbitrary buffer of 1024

;;; We have created a user process, so we need to increment the static that is keeping track of how many user processes are running.
	ADDUS		*+_user_process_count		*+_user_process_count		1
;;; We also want to increase the length of the process table
	ADDUS		*+_pt_length			*+_pt_length			48


	
;;; ;  Epilogue: Pop and restore preserved registers, then return.

	COPY            %G4             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G3             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G0             *%SP
	ADDUS           %SP             %SP             4
 	ADDUS		%G5		%FP		12 ;%G5 = &ra

	
	JUMP            *%G5

	
;;; ; ; ; ================================================================================================================================
;;; ; ; ; Procedure: _init2_proc_entry (initializes a process table in the heap...does not set the "empty" entries to zero
;;; ; ; ; Callee preserved registers:
;;; ; ; ;   [%FP - 4]: G0
;;; ; ; ;   [%FP - 8]: G3
;;; ; ; ;   [%FP - 12]: G4
;;; ; ; ; Parameters:
;;; ; ; ;   [%FP + 0]: RAM[base]
;;; ; ; ;   [%FP + 4]: RAM[limit]
;;; ; ; ;   [%FP + 8]: Process ID
;;; ; ; ;   [%FP + 12]: &base of process entry.
;;; ; ; ; Caller preserved registers:
;;; ; ; ;   [%FP + 16]: FP
;;; ; ; ; Return address:
;;; ; ; ;   [%FP + 20]
;;; ; ; ; Return value:
;;; ; ; ;   <none>
;;; ; ; ; Locals:
;;; ; ; ;   %G0: RAM[base]
;;; ; ; ;   %G1: &ptr_to_heap
;;; ; ; ;   %G2: address that we are at in process table	
;;; ; ; ;   %G3: RAM[limit]
;;; ; ; ;   %G4: Process ID

_init2_proc_entry:
	
;;; ; ; Callee  Prologue: Preserve registers

	SUBUS           %SP             %SP             4
	COPY            *%SP            %G0
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G1
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G2	
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G3
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G4

;;; ; ; Initialize locals

	;; Locals whose values are taken from the stack. 
	COPY 		%G0		*%FP		  ; %G0 = RAM[base]
	ADDUS           %G3             %FP             4
	COPY 		%G3		*%G3		  ; %G3 = RAM[limit]
	ADDUS           %G4             %FP             8
	COPY 		%G4		*%G4		  ; %G4 = &Pid
	COPY		%G4		*%G4		  ; %G4 = Pid
	ADDUS           %G1             %FP             12
	COPY 		%G1		*%G1		  ; %G1 = &Processtable

;;; Ensure that the process table has been initialized.

;;; If not, initialize it.
	
_init_process_table:
	;; if we are intitializing, set the process ID number in the heap to process ID
	COPY		*%G1		%G4


_find_proc_entry_loop_end2:

	;; Now, set the base and limit variables for the process.
	ADDUS		%G1		%G1		4 ; %G1 = &process_table[base]
	COPY		*%G1		%G0		  ; process_table[base] = RAM[base]
	ADDUS		%G1		%G1		4 ; %G1 = &process_table[limit]
	COPY		*%G1		%G3		  ; process_table[limit] = RAM[limit]
	ADDUS		%G1		%G1		4 ; %G1 = &process_table[IP]
	COPY		*%G1		0		  ; ensure that IP starts at 0
	
	;; We're done, let's clean up (restore registers) and return.
        COPY            %G4             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G3             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G2             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G1             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G0             *%SP
	ADDUS           %SP             %SP             4

	ADDUS           %G5             %FP             20 ;%G5 = &ra
	JUMP            *%G5

	
	
;;; ; ; ================================================================================================================================
;;; ; ; 							INTERRUPT HANDLERS
;;; ; ; ================================================================================================================================
	

sysc_int_handler:
	;; make sure the clock alarm is off
	SETALM		*+shut_off_clk		1
	;; check to see if the interrupt came from the kernel, if it did, panic
	BEQ		+_kernel_panic		*+_static_kernel_int		1
	;; else, continue
	COPY		*+_static_kernel_int		1
	
;;; ; ; ; Callee  Prologue: Preserve registers
;;; ;	Inspects the value in register %G1 to determine to Create, Exit, or GetRomCount

	BEQ		+sysc_int_create		%G1		1
	BEQ		+sysc_int_exit			%G1		2
	BEQ		+sysc_int_getromcount		%G1		3

sysc_int_create:

;;; Callee prologue to preserve registers.
	
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G0
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G3
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G4

;;; ; Caller Prologue to CREATE:

	SUBUS           %SP             %SP             12 ; Push pfp / ra / rv
	COPY            *%SP            %FP 		   ; pFP = %FP
	SUBUS           %SP             %SP             4  ; Push arg[1]
	COPY            *%SP            %G0 		   ; we are assuming that we left the ROM that we want in %G0
	SUBUS           %SP             %SP             4  ; Push arg[0]
	COPY            *%SP            *+_static_ROM_device_code ; Find a ROM device.
	COPY            %FP             %SP 		   ; Update %FP
	ADDUS           %G5             %SP             12 ; %G5 = &ra
	CALL            +_CREATE2         *%G5
	ADDUS           %SP             %SP             8  ; Pop arg[0,1]
	COPY            %FP             *%SP 		   ; %FP = pfp
	ADDUS           %SP             %SP             8  ; Pop pfp / ra
	COPY            %G4             *%SP 		   ; %G4 = RAM[base]
	ADDUS           %SP             %SP             4  ; Pop rv
	;; JUMPMD		%G4		0b10
	ADDUS		*+IB_IP			*+IB_IP			16

	ADDUS		%G0		+_heap_process_table		4 ; Base of process 3, from the process table.
	ADDUS		%G3		+_heap_process_table		8 ; Limit of process 3, from the process table

 	SETBS		*%G0
 	SETLM		*%G3

	;; we just jump back into the IB_IP because we are always going to just be jumping back into the 3rd process here (init)
	COPY		*+_static_kernel_int			0 ;no longer gonna be in the kernel
	;; jump back into the init.asm file
	JUMPMD		*+IB_IP			0b110


	
sysc_int_exit:
	
;;; ; Callee preserved registers: 
;;; 	[%FP - 4]:  G4
;;; ; Parameters: None
;;; ; Caller preserved registers:
;;; ;   [%FP + 0]:  FP
;;; ; Return address:
;;; ; Return value:
;;; ;   None
;;; Locals: %G4: Used to iterate through process table
;;; ;;; Locals: %G3: Used to store last address of the process table

	;; First, check to see that there will be remaining processes once we exit this one
	SUBUS		*+_user_process_count		*+_user_process_count		1
	BNEQ		+_call_scheduler		*+_user_process_count		0
	;; If there are no processes left to run (i.e. if _user_process_count is zero), HALT the kernel
	
	HALT
	
_call_scheduler:	
;;; Caller Prologue to scheduler.

	;; check to see if the kernel SP and FP preservers have been initialized.
	BEQ		+make_the_call		*+_kernel_sp_pres	0
	;;  if they have been initialized, use them to restore the kernel SP and FP values
	COPY		%SP			*+_kernel_sp_pres
	COPY		%FP			*+_kernel_fp_pres

make_the_call:
	;; The kinda ad hoc way which the is written right now won't allow us to return to this call, so preserve %SP and %FP
	;; Since we are going into a user process that may use the SP and FP, we must preserve the kernel's SP and FP
	COPY		*+_kernel_sp_pres		%SP
	COPY		*+_kernel_fp_pres		%FP
	

	SUBUS           %SP             %SP             8 ; Push pfp / ra
	COPY            *%SP            %FP 		   ; pFP = %FP
	SUBUS           %SP             %SP             4  ; Push arg[0]
	COPY		*%SP		1		   ; We are setting this to 1 to signify that this call to scheduler is coming from EXIT
	COPY            %FP             %SP 		   ; Update %FP
	ADDUS           %G5             %SP             8 ; %G5 = &ra
	CALL            +_scheduler     *%G5
	ADDUS           %SP             %SP             4  ; Pop arg[0]
	COPY            %FP             *%SP 		   ; %FP = pfp
	ADDUS           %SP             %SP             8  ; Pop pfp / ra


	
sysc_int_getromcount:

	;; in a perfect world, the registers used below would all be preserved
	
	SUBUS           %SP             %SP             12 ; Push pfp / ra / rv
	COPY            *%SP            %FP 		   ; pFP = %FP
	COPY            %FP             %SP 		   ; Update %FP
	ADDUS           %G5             %SP             4  ; %G5 = &ra
	CALL            +GET_ROM_COUNT     *%G5
	COPY            %FP             *%SP 		   ; %FP = pfp
	ADDUS           %SP             %SP             8  ; Pop pfp / ra
	COPY		%G1		*%SP		   ; Leave the return value in %G1 for the init file.

		;; We'll use register %G0 to hold the base of process 3 (which we take from the process table)
	ADDUS		%G0		+_heap_process_table		4 ; Base of process 3, from the process table.
	ADDUS		%G3		+_heap_process_table		8 ; Limit of process 3, from the process table

 	SETBS		*%G0
 	SETLM		*%G3

	COPY		*+_static_kernel_int		0 ; we are no longer in the kernel.
	ADDUS		*+IB_IP				*+IB_IP			16
	JUMPMD		*+IB_IP				0b110
	
	
clock_int_handler:

	;; check to see if the interrupt came from the kernel, if it did, panic
	BEQ		+_kernel_panic		*+_static_kernel_int		1
	;; else, continue
	COPY		*+_static_kernel_int		1

	;; Caller Subframe

		;; check to see if the kernel SP and FP preservers have been initialized.
	BEQ		+make_a_call		*+_kernel_sp_pres	0
	;;  if they have been initialized, use them to restore the kernel SP and FP values
	COPY		%SP			*+_kernel_sp_pres
	COPY		%FP			*+_kernel_fp_pres

make_a_call:
	;; The kinda ad hoc way which the is written right now won't allow us to return to this call, so preserve %SP and %FP
	;; Since we are going into a user process that may use the SP and FP, we must preserve the kernel's SP and FP
	COPY		*+_kernel_sp_pres		%SP
	COPY		*+_kernel_fp_pres		%FP
	

	SUBUS           %SP             %SP             8 ; Push pfp / ra
	COPY            *%SP            %FP 		   ; pFP = %FP
	SUBUS           %SP             %SP             4  ; Push arg[0]
	COPY		*%SP		0		   ; We are setting this to 1 to signify that this call to scheduler is coming from clock_int
	COPY            %FP             %SP 		   ; Update %FP
	ADDUS           %G5             %SP             8 ; %G5 = &ra
	CALL            +_scheduler     *%G5
	ADDUS           %SP             %SP             4  ; Pop arg[0]
	COPY            %FP             *%SP 		   ; %FP = pfp
	ADDUS           %SP             %SP             8  ; Pop pfp / ra


	
def_int_handler:
	;; check to see if the interrupt came from the kernel, if it did, panic
	BEQ		+_kernel_panic		*+_static_kernel_int		1
	;; else, continue
	COPY		*+_static_kernel_int		1
	COPY		%G2		%G2
	HALT

invinst_int_handler:
	;; check to see if the interrupt came from the kernel, if it did, panic
	BEQ		+_kernel_panic		*+_static_kernel_int		1
	;; else, continue
	COPY		*+_static_kernel_int		1
	COPY		%G3		%G3
	HALT

perm_int_handler:
	;; check to see if the interrupt came from the kernel, if it did, panic
	BEQ		+_kernel_panic		*+_static_kernel_int		1
	;; else, continue
	COPY		*+_static_kernel_int		1
	COPY 		%G4		%G4
	HALT

bus_err_int_handler:
	;; check to see if the interrupt came from the kernel, if it did, panic
	BEQ		+_kernel_panic		*+_static_kernel_int		1
	;; else, continue
	COPY		*+_static_kernel_int		1
	COPY		%G5 		%G5
	HALT
	
_kernel_panic:

	HALT
;;; ; ================================================================================================================================

	
.Numeric

;;;  A special marker that indicates the beginning of the statics.  The value is just a magic cookie, in case any code wants
;;;  to check that this is the correct location (with high probability).
_static_statics_start_marker:	0xdeadcafe

;;;  Device table location and codes.
_static_device_table_base:		0x00001000
_static_dt_entry_size:			12
_static_dt_base_offset:			4
_static_dt_limit_offset:		8
_static_none_device_code:		0
_static_controller_device_code:		1
_static_ROM_device_code:		2
_static_RAM_device_code:		3
_static_console_device_code:		4

;;;  Error codes.
_static_kernel_error_RAM_not_found:		0xffff0001
_static_kernel_error_main_returned:		0xffff0002
_static_kernel_error_small_RAM:			0xffff0003
_static_kernel_error_console_not_found:		0xffff0004
_static_kernel_error_ROM_not_found:		0xffff0005
_static_kernel_error_ROM_not_found_see_CREATE2:		0xffff0006
	
;;;  Constants for printing and console management.
_static_console_width:			80
_static_console_height:			24
_static_space_char:			0x20202020 ; Four copies for faster scrolling.  If used with COPYB, only the low byte is used.
_static_cursor_char:			0x5f
_static_newline_char:			0x0a

;;;  Other constants.
_static_min_RAM_KB:			64
_static_bytes_per_KB:			1024
_static_bytes_per_page:			4096 ; 4 KB/page
_static_kernel_KB_size:			32   ; KB taken by the kernel.
_static_pt_entry_size:			0x44 ; number of bytes required for a process table entry
;;;  Statically allocated variables.
_static_cursor_column:			0 ; The column position of the cursor (always on the last row).
_static_RAM_base:			0
_static_RAM_limit:			0
_static_console_base:			0
_static_console_limit:			0
_static_kernel_base:			0
_static_kernel_limit:			0
_static_3rd_ROM_base:			0
_static_3rd_ROM_limit:			0
_static_mem_base:			0 ; keeps track of where we will load the next program that's created
_static_ROM_to_load:			3 ; keeps track of the next ROM that we will want to load a program from (used in the _CREATE function)

;;; Detect if interrupt is coming from the kernel.
_static_kernel_int:			1 ; will be 0 if we are not in the kernel, 1 if we are in the kernel.
	
;;; Statics for preservation of kernel SP and FP.
_kernel_sp_pres:	0
_kernel_fp_pres:	0
	
;;; Statics for the clock interrupt handler
counter:				0
fpTemp:					0
spTemp:					0
temp_G0:				0
	
;;; Statics for handling processes (these are used in the CREATE and EXIT system calls).
_current_user_process_id:		0 ; keeps track of the process that we just left
_user_process_count:			0 ; keeps track of the number of processes running (if this hits zero, we know to shut down the kernel)
_pt_length:				0 ; keeps track of the length of the process table

;;; Statics for SYSC
shut_off_clk:				0 ; shut off the clock
shut_off_clk1:				0
	
;;; Statics for the EXIT system call
_temp_G4:				0 ; used in the EXIT system call for restoration of registers

;;; Statics for the scheduler
_scheduler_return_address:		0 ; might be used to finish scheduler function call

	
;;; Statics for the clock interrupt
_clk_alm:				0x0 		;first word of two-word value containing how many instructions to process before throwing an interrupt
_clk_alm2:				50		;second word of two-word value containing how many instructions to process before throwing an interrupt
	
;;; Trap table. Self-explanatory variables
tt_base:
	INVALID_ADDRESS:	0
	INVALID_REGISTER:	0
	BUS_ERROR:	0
	CLOCK_ALARM:	0
	DIVIDE_BY_ZERO:	0
	OVERFLOW:	0
	INVALID_INSTRUCTION:	0
	PERMISSION_VIOLATION:	0
	INVALID_SHIFT_AMOUNT:	0
	SYSTEM_CALL:	0
	INVALID_DEVICE_VALUE:	0
	DEVICE_FAILURE:	0

;;; Interrupt Buffer
IB_IP:	  			0
	IB_MISC:	        0

;;; ; ================================================================================================================================



;;; ; ================================================================================================================================
	.Text

_string_banner_msg:		"k-System kernel r0 2010-06-25\n"
_string_copyright_msg:		"(c) Scott F. H. Kaplan / sfkaplan@cs.amherst.edu\n"
_string_done_msg:		"done.\n"
_string_abort_msg:		"failed!  Halting now.\n"
_string_initializing_init:	"We are about to JUMPMD into init.vmx"
_string_blank_line:		"                                                                                "
_string_to_init:		"We are about to jump into the init file. We are jumping into init from main. We will being creating our processes."
_string_kernel_int_thrown:	"An interrupt was thrown in the kernel. Halting the processor."
_string_process_created:	"A process has been successfully created."
_string_process_exited:		"A process has been successfully exited."
;;; ; ================================================================================================================================
	;; The top of the heap will come after the code and statics.

.Numeric
_heap_top:		0
_heap_next_free_block:		0
	;; This is going to be a pointer to the beginning of the process table. When the process table is initialized, we will store the number of ROMs in here. If we know the number of ROMs, we will know how many processes we will need to allocate space for.
_heap_process_table:	0xffffffff ; this is just a code indicating that the process table hasnt been initialized
	
