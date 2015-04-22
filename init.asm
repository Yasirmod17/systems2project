;;; ; Tomal Hossain/Conner John/Mohammed Ibrahim



.Code

;;; we are going to make a loop: while we havent created all the processes, we will throw a SYSC and create the next process

	;; we know that the first ROM we will want to load will be #4, so let's start %G0 at 4 - this means we can also use %G0 to know which process to load
	COPY %G0 4
	
_create_all_proc:	

	SYSC
	BEQ +_finished_creating %G0 total_num_roms
	ADD %G0 %G0 1
	JUMP +_create_all_proc
	
_finished_creating:	

	HALT


.Numeric

	
total_num_roms:	5
