;;;

.Code

;;; register %G0 is going to keep track of the address in the bus controller
 	COPY %G0 *+bc_address
	
;;; register %G1 is going to count how many roms we have found
	COPY %G1 0x0
	
;;; check the value in 0x1000

startloop1:
;;; if the value at address %G0 is 2, then we are going to branch to rom_match
	BEQ +rom_match *%G0 *+rom_number

;;; otherwise, we are going to increment the address in %G0 by 12 and then check it again
	ADD %G0 %G0 12
	JUMP +startloop1
	
;;; if we have found a device match, then we want to increment the number of roms we have found. if its two, then we've found the kernel
rom_match:	

	ADD %G1 %G1 1
;;; if we have found 2 roms, then we have found the kernel and we can store the address at which we found it, along with the base and limit of the kernel
	BEQ +endloop1 %G1 2
	ADD %G0 %G0 12
	JUMP +startloop1
	
endloop1:

 	ADD %G0 %G0 4
;;; 	HALT
	
;;; we now know that register %G0 contains the address at which the second ROM begins

;;; now lets find the RAM, we'll put the address at which we find the BC info in register %G1

;;; set register %G1 to the beginning of the bus controller
	
	COPY %G1 *+bc_address

startloop2:	
	
;;; if the value at address %G1 is 3, then we are going to branch to ram_match
	BEQ +ram_match *%G1 *+ram_number
;;; if the value is 0, then we are at the end of the device table and we didnt find anything
	BEQ +device_not_found	*%G1	0
	
;;; otherwise, we are going to increment the address in %G1 by 12 and check it again
	ADD %G1 %G1 0xc
	JUMP +startloop2
	
ram_match:
;;; now we have the bus controller addresses with the info for RAM and the kernel
	ADD %G1 %G1 0x4
	
;;; we now know that if we do 'JUMP *%G1', then we will be at the beginning of RAM

;;; copy the kernel (i.e. the 2nd ROM) into main memory (RAM)

;;; let's make this easy and copy the addresses stored at %G0 and %G1 into other registers

;;; register %G2 will contain the address marking the beginning of the kernel

	COPY %G2 *%G0

	;; JUMP %G2
	
;;; register %G3 will contain the beginning of RAM

	COPY %G3 *%G1
	
;;; register %G4 will contain the limit of the kernel+16
	;; first, let's increment register %G0 by 4 to get to the 'bc' address containing the kernel limit

	ADD %G4 %G0 0x4
	COPY %G4 *%G4
	
;;; 	ADD %G4 %G4 16

	
copyKernelLoop:
	
	;; COPY %G3 %G2
	COPY *%G3 *%G2
	ADD %G2 %G2 4
	ADD %G3 %G3 4

;;; check to see if we have iterated through the entirety of the kernel's contents
	BEQ +endCopyKernelLoop %G4 %G2

	JUMP +copyKernelLoop
	
endCopyKernelLoop:
	
;;; JUMP to the copied kernel's first machine code instruction
	JUMP *%G1

device_not_found:	
	HALT

.Numeric
;;; "bc" is short for "bus controller"
bc_address:	0x1000
bc_counter:	0x0
bc_increment:	0x4
;;; "dev" is short for "device"
rom_number:	0x2
ram_number:	0x3
