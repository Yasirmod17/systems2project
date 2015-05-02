;;; ; Tomal Hossain/Conner John/Mohammed Ibrahim

.Code

;;; First, get the number of ROMs.
	COPY		%G1		3 ; signify a GETROMCOUNT sysc
	SYSC
;;; When we return, we set total roms to the number left in %G1
	COPY		*+total_num_roms		%G1
;;; we are going to make a loop: while we havent created all the processes, we will throw a SYSC and create the next process
	
	COPY %G0 *+last_proc_created
	
_create_all_proc:	
	BEQ	+_finished_creating		*+last_proc_created 		*+total_num_roms
	ADD		*+last_proc_created		*+last_proc_created		1
	COPY 		%G0		*+last_proc_created
	COPY		%G1		1 ; signify a CREATE system call
	SYSC
	JUMP +_create_all_proc
	
_finished_creating:	

	COPY		%G1		2 ; signify an EXIT system call
	SYSC


.Numeric
;; we know that the first ROM we will want to load will be #4, so let's start this static at 3
last_proc_created:	3
total_num_roms:	5
