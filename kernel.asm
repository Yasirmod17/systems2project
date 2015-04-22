;;; ; ================================================================================================================================
;;; ; kernel-stub.asm
;;; ; Conner Reilly / Tomal Hossain / Mohammed Ibrahim
;;; ;
;;; ; The assembly core that perform the basic initialization of the kernel, bootstrapping the installation of trap handlers and
;;; ; configuring the kernel's memory space.
;;; ;
;;; ; Revision 0 : 2010-09-06
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
	COPY 		*+BUS_ERROR 		+sysc_int_handler
;;; ; it looks like right now on a CLOCK_ALARM, the simulator will vector to what I set for the PERMISSION_VIOLATION interrupt
	COPY 		*+PERMISSION_VIOLATION		+sysc_int_handler
	COPY 		*+CLOCK_ALARM 			+sysc_int_handler
	COPY 		*+SYSTEM_CALL 			+sysc_int_handler
	COPY 		*+INVALID_INSTRUCTION 		+def_int_handler


	
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
;;; ; ;   [%FP + 0]: A pointer to the beginning of a null-terminated string.
;;; ; ; Caller preserved registers:
;;; ; ;   [%FP + 4]: FP
;;; ; ; Return address:
;;; ; ;   [%FP + 8]
;;; ; ; Return value:
;;; ; ;   <none>
;;; ; ; Locals:
;;; ; ;   %G0: Pointer to the current position in the string.  

	
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
	CALL            +_CREATE         *%G5		   ; CREATE the init process
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
	;; Caller prologue for print.
        SUBUS           %SP             %SP             8 	; Push pfp / ra (no return value)
	COPY            *%SP            %FP	   		; pFP = %FP
	SUBUS           %SP             %SP             4 	; Push arg[0]
	COPY            *%SP            +_string_initializing_init ; Print out msg indicating we are jumping into init.
	COPY            %FP             %SP 			; Update %FP
	ADDUS           %G5             %SP             8 	; %G5 = &ra
	CALL            +_procedure_print         *%G5          ; CALL print. 
        ADDUS           %SP             %SP             4	; Pop arg[0]
	COPY            %FP             *%SP            	; %FP = pfp
	ADDUS           %SP             %SP             8 	; Pop pfp / ra

	JUMPMD		 *+p1_base		0b10
	

	
;;; Epilogue: Pop and restore preserved registers, and then return
	

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
;;; ; ; Procedure: _CREATE
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

_CREATE:
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
	BNEQ            +_CREATE_found_ROM    %G4             0
	COPY            %G5             *+_static_kernel_error_console_not_found
	HALT

_CREATE_found_ROM:
	ADDUS           %G3             %G4             *+_static_dt_base_offset	; %G3 = &nthROM[base]
	COPY            %G0		*%G3						; %G0 = ROM[base]
	ADDUS           %G3             %G4             *+_static_dt_limit_offset 	; %G3 = &nthROM[limit]
	COPY            %G3		*%G3						; %G3 = ROM[limit]
	
	COPY 		%G4	*+_static_mem_base					; store base of the first free chunk of memory in %G4

_CREATE_copy_loop_top:
	
	COPY		*%G4	 	*%G0 						; copy the contents of the nth ROM into RAM, one word at a time
	ADD		%G0		%G0		4
	ADD 		%G4 		%G4 		4
	
	BEQ 		+_CREATE_copy_loop_end 		%G0 		%G3 		; check to see if we have copied all contents from the ROM
	
	JUMP 		+_CREATE_copy_loop_top

_CREATE_copy_loop_end:

	;; The program has now been copied into RAM. Now, what we want is to CALL init_proc_entry(RAM[base], RAM[limit], process ID)

	;; Caller prologue to init_proc_entry
        SUBUS           %SP             %SP             8 				; Push pfp / ra (no return value)
	COPY            *%SP            %FP	   					; pFP = %FP
	SUBUS           %SP             %SP             4 				; Push arg[2]
	ADDUS            *%SP            %FP		4  				; arg[2] = &ROM instance number
	SUBUS           %SP             %SP             4				; Push arg[1]
	COPY            *%SP            %G4 						; arg[1] = RAM[limit] (limit = word after last word of prog)
	SUBUS           %SP             %SP             4				; Push arg[0]
	COPY            *%SP            *+_static_mem_base	 			; arg[0] = RAM[base]	
	COPY            %FP             %SP 						; Update %FP
	ADDUS           %G5             %SP             16 				; %G5 = &ra
	CALL            +_init_proc_entry	         *%G5 				; CALL init_proc_entry
        ADDUS           %SP             %SP             12 				; Pop arg[0,1,2]
	COPY            %FP             *%SP	  					; %FP = pfp
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
	
;;; ;  Epilogue: Pop and restore preserved registers, then return.

	COPY            %G4             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G3             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G0             *%SP
	ADDUS           %SP             %SP             4
 	ADDUS		%G5		%FP		12 ;%G5 = &ra
	JUMP            *%G5
	
	JUMPMD *+_static_mem_base 0b10


	
	
;;; ; ; ================================================================================================================================


;;; ; ; ; ================================================================================================================================
;;; ; ; ; Procedure: _init_proc_entry
;;; ; ; ; Callee preserved registers:
;;; ; ; ;   [%FP - 4]: G0
;;; ; ; ;   [%FP - 8]: G3
;;; ; ; ;   [%FP - 12]: G4
;;; ; ; ; Parameters:
;;; ; ; ;   [%FP + 0]: RAM[base]
;;; ; ; ;   [%FP + 4]: RAM[limit]
;;; ; ; ;   [%FP + 8]: Process ID
;;; ; ; ; Caller preserved registers:
;;; ; ; ;   [%FP + 12]: FP
;;; ; ; ; Return address:
;;; ; ; ;   [%FP + 16]
;;; ; ; ; Return value:
;;; ; ; ;   <none>
;;; ; ; ; Locals:
;;; ; ; ;   %G0: RAM[base]
;;; ; ; ;   %G2: address that we are at in process table	
;;; ; ; ;   %G3: RAM[limit]
;;; ; ; ;   %G4: Process ID

_init_proc_entry:
	
;;; ; ; Callee  Prologue: Preserve registers

	SUBUS           %SP             %SP             4
	COPY            *%SP            %G0
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
	COPY            %G3             *%G3		  ; %G3 = RAM[limit]
	ADDUS		%G4		%FP		8
	COPY		%G4		*%G4 		  ; %G4 = &Process ID
	COPY		%G4		*%G4 		  ; %G4 = Process ID

	;; 	BEQ		+debugging_shit		%G4		4
	
	;; Other locals.
	COPY 		%G2		+process_table
	
;;; 
_find_proc_entry_loop_top:

	;; Find the entry in the process table that we are looking for.
	BEQ		+_find_proc_entry_loop_end		%G4		*%G2
	ADDUS		%G2					%G2		48
	JUMP		+_find_proc_entry_loop_end

_find_proc_entry_loop_end:

	;; Now, set the base and limit variables for the process.
	ADDUS		%G2		%G2		4 ; %G2 = &process_table[base]
	COPY		*%G2		%G0		  ; process_table[base] = RAM[base]
	ADDUS		%G2		%G2		4 ; %G2 = &process_table[limit]
	COPY		*%G2		%G3		  ; process_table[limit] = RAM[limit]

	;; We're done, let's clean up (restore registers) and return.
        COPY            %G4             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G3             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G2             *%SP
	ADDUS           %SP             %SP             4
	COPY            %G0             *%SP
	ADDUS           %SP             %SP             4
	ADDUS           %G5             %FP             16 ;%G5 = &ra
	JUMP            *%G5

debugging_shit:
	
	JUMPMD		%G0		0b10
	
;;; ; ; ================================================================================================================================
	;; INTERRUPT HANDLERS

sysc_int_handler:
;;; ; ; Callee  Prologue: Preserve registers

	SUBUS           %SP             %SP             4
	COPY            *%SP            %G0
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G3
	SUBUS           %SP             %SP             4
	COPY            *%SP            %G4

;;; ; Caller Prologue to find device:
;;; ; If not yet initialized, set the console base/limit statics.
;;; ;             BNEQ            +print_init_loop        *+_static_console_base          0
	
	SUBUS           %SP             %SP             12 ; Push pfp / ra / rv
	COPY            *%SP            %FP 		   ; pFP = %FP
	SUBUS           %SP             %SP             4  ; Push arg[1]
	COPY            *%SP            %G0 		   ; we are assuming that we left the ROM that we want in %G0
	SUBUS           %SP             %SP             4  ; Push arg[0]
	COPY            *%SP            *+_static_ROM_device_code ; Find a ROM device.
	COPY            %FP             %SP 		   ; Update %FP
	ADDUS           %G5             %SP             12 ; %G5 = &ra
	CALL            +_CREATE         *%G5
	ADDUS           %SP             %SP             8  ; Pop arg[0,1]
	COPY            %FP             *%SP 		   ; %FP = pfp
	ADDUS           %SP             %SP             8  ; Pop pfp / ra
	COPY            %G4             *%SP 		   ; %G4 = RAM[base]
	ADDUS           %SP             %SP             4  ; Pop rv
	;; JUMPMD		%G4		0b10
	JUMPMD		%G4			0b10
	
clock_int_handler:
	HALT

def_int_handler:
	HALT

invinst_int_handler:
	HALT

perm_int_handler:	
	HALT
bus_err_int_handler:
	COPY %G0 %G0
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
;;; Trap table. Self-explanatory variables
tt_base:
	BUS_ERROR:	      0
	PERMISSION_VIOLATION:	   0
	CLOCK_ALARM:	    0
	SYSTEM_CALL:	    0
	INVALID_INSTRUCTION:	0
	
;;; Process table:
process_table:
;;; ; for now I'll just pretend that i only have two processes

;;; ; process 1

;;; ; I'm going to say that process 1 has a pid of 4 so that we can just use the "process_number" static variable \
;;; 	to find the entry in the process table that we are looking for (this means process 2 will have a pid of 5, etc.)
	pid1:	   3
	p1_base:	 0
	p1_limit:	 0
	_ip1:	 0
	pres_1_G0:	 0
	pres_1_G1:	 0
	pres_1_G2:	 0
	pres_1_G3:	 0
	pres_1_G4:	 0
	pres_1_G5:	 0
	pres_1_sp:	 0
	pres_1_fp:	 0

;;; ; process 2
	pid2:	       4
	p2_base:	         0
	p2_limit:	        0
	_ip2:	    0
	pres_2_G0:	       0
	pres_2_G1:	       0
	pres_2_G2:	       0
	pres_2_G3:	       0
	pres_2_G4:	       0
	pres_2_G5:	       0
	pres_2_sp:	       0
	pres_2_fp:	       0

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
;;; ; ================================================================================================================================
