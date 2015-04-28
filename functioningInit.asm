;;; Conner Reilly
;;; 04/17/15

;;; this code will sum the values from the array in the .Numerics
	
.Code

;;; register %G0 is going to count how many elements we've summed up in the array
	COPY %G0 0
;;; register %G1 is going to hold the array.length
	COPY %G1 *+array
;;; register %G2 is going to hold the running sum
	COPY %G2 0
;;; register %G3 is going to hold the address we want to take the value from
	COPY %G3 +array
	ADD %G3 %G3 4
	
_sum:	

	BEQ +_end_program %G0 %G1

	ADD %G2 %G2 *%G3

	ADD %G0 %G0 1

	JUMP +_sum
	
_end_program:
	
	COPY	%G1	2	; signify an EXIT system call
	SYSC
.Numeric


array:
	10
	1
	2
	3
	4
	5
	6
	7
	8
	9
	10
