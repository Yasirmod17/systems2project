;;; A simple program that adds two numbers, demonstrating a few of the
;;; 	addressing modes.

	
.Code

;;; The entry point.
__start:
	;; Initialize the stack at the limit.
	;; 	COPY	%SP	*+limit

	;; Copy one of the source values into a register.
	COPY	%G0	*+x
	
	;; Allocate a space on the stack for the result.
	;; SUBUS	%SP	%SP	4

	;; Sum the two values.  In particular:
	;;   src A (%G0): A value taken from a register.
	;;   src B (*+y): A indirect value stored in a static space named by a label.
	;;   dst   (%SP): A register that contains a pointer to a main memory space.
	;; for now, no %SP in user processes
	ADD	%G1	%G0	*+y

	COPY		%G0		2 ; signify an exit SYSC by setting %G0 to 2
	;; Halt the processor.
	SYSC
	
end:	

.Numeric

	;; The source values to be added.
x:	5
y:	-3

	;; Assume (at least) a 16 KB main memory.
limit:	0x5000
