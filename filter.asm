.data
		
header:		.space 56
size:		.space 4  # space for input image bitmap size in bytes
width:		.space 4  # space for image width in pixels
height:		.space 4  # space for image height in pixels

welcomeMsg:	.asciiz "High Pass / Low Pass filter\n   Michal Sieczkowski 04.2017\n\n"
openedMsg:	.asciiz "File opened\n   Processing...\n"
errorMsg:	.asciiz "Error opening/reading file\n"
inFileName:	.asciiz "input_big2.bmp"
outFileName:	.asciiz "input_big21.bmp"


debugWidth: 	.asciiz "Width: "
debugHeight: 	.asciiz "\nHeight: "
debugSize:	.asciiz "\nSize: "
debugNewLine:   .asciiz "\n"

.text
.globl main

main:
	# Welcome message:
	la $a0, welcomeMsg
	li $v0, 4
	syscall
	
	
	# -----------------------  Reading the header  -----------------------------
	# $t0 - input file descriptor
	# $t1 - output file descriptor
	# $s0 - bitmap size
	# $s1 - width in pixels
	# $s2 - height in pixels
	# --------------------------------------------------------------------------
	
	
	# Open input file for reading:
	la $a0, inFileName	# file name
	li $a1, 0		# open for reading only
	li $a2, 0		# mode is ignored
	li $v0, 13		# open file
	syscall

	move $t0, $v0 		# save file descriptor in $t0 (negative if error)
	bltz $t0, fileError	# exit program if error occured
	
	
	# Open output file for writing:
	la $a0, outFileName	# file name
	li $a1, 1		# open for writing
	li $a2, 0		# mode is ignored
	li $v0, 13		# open file
	syscall
	
	move $t1, $v0 		# save file descriptor in $t1 (negative if error)
	bltz $t1, fileError	# exit program if error occured
	
	
	# Success opening files message:
	la $a0, openedMsg
	li $v0, 4
	syscall
	
	
	# Reading the header:
  	move $a0, $t0     	# input file descriptor
	la   $a1, header+2   	# input buffer address
  	li   $a2, 54		# num of characters to read
  	li   $v0, 14  	 	# read from file
  	syscall			
	
	lw $s0, header+4	# load file size
	lw $s1, header+20	# load image width
	lw $s2, header+24	# load image height
	
	sub $s0, $s0, 54
	sw  $s0, size		# store image bitmap size
	sw  $s1, width		# store image width
	sw  $s2, height		# store image height
	
	
	### TODO: Check: #############################
	##	 	*the size of header (54)    ##
	##		*bits per pixel (24)        ##
	##		*first two bytes ale "BM"   ##
	##############################################
	
##DEBUG----------------------------------

	la $a0, debugWidth 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s1
	syscall
	
	la $a0, debugHeight 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s2
	syscall
	
	la $a0, debugSize 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s0
	syscall
	
	la $a0, debugNewLine 	
	li $v0, 4
	syscall

##DEBUG-END----------------------------------


	# Write header to output file:
	move $a0, $t1        # output file descriptor 
	la   $a1, header+2   # address of buffer from which to write
	li   $a2, 54         # header length
	li   $v0, 15         # write to file
	syscall
	
	# Allocate in buffer space:
	move $a0, $s0        # number of bytes to allocate 
	li   $v0, 9          # allocate
	syscall
	move $t5, $v0	     # address of allocated memmory
	
	# Allocate out buffer space:
	move $a0, $s0        # number of bytes to allocate 
	li   $v0, 9          # allocate
	syscall
	move $t7, $v0	     # address of allocated memmory
	
	# Calculate row size:
	mul $s3, $s1, 24	# The formula is:	
	addi $s3, $s3, 31	# floor((24*width + 32) / 32) * 4
	li $t2, 32
	div $s3, $t2		# Floor is achived by taking the quotient of division
	mflo $s3
	mul $s3, $s3, 4
	### $s3 now holds row size
	
	# Calculate padding:
	mul $t2, $s1, 3 
	sub $t9, $s3, $t2
	### $t9 now holds padding

	
	
readToBuffer:
	# Read to buffer:
  	move $a0, $t0     	# input file descriptor
	move $a1, $t5   	# input buffer address
  	move $a2, $s0		# max num of characters to read
  	li   $v0, 14  	 	# read from file
  	syscall	
  	move $t2, $v0		
  	bltz $t2, fileError
###----------------------------  	
  	move $a0, $t0      # input file descriptor to close
	li   $v0, 16       # close file 
	syscall
	
	la $a0, inFileName	# file name
	li $a1, 0		# open for reading only
	li $a2, 0		# mode is ignored
	li $v0, 13		# open file
	syscall

	move $t0, $v0 		# save file descriptor in $t0 (negative if error)
	bltz $t0, fileError	# exit program if error occured
	
  	move $a0, $t0     	# input file descriptor
	la   $a1, header+2   	# input buffer address
  	li   $a2, 54		# num of characters to read
  	li   $v0, 14  	 	# read from file
  	syscall
  	
  	move $a0, $t0     	# input file descriptor
	move $a1, $t7   	# input buffer address
  	move $a2, $s0		# max num of characters to read
  	li   $v0, 14  	 	# read from file
  	syscall	
  	move $t2, $v0		
  	bltz $t2, fileError
  	
 ###-----------------------------
  	
  	###### s0 s1 s2 will be reused from now on ######
	
	li $s0, 14 # center
	li $s1, -1 # edge
	li $s2, -1 # corner
	mul $s6, $s1, 4
	mul $s7, $s2, 4
	add $s6, $s6, $s7
	add $s6, $s6, $s0  # sum of factors 
  	 
  
  	move $t3, $s3
	lw $t8, size
	sub $t8, $t8, $s3
  	
nextRow:
  	#End of row position:
  	add $t4, $t3, $s3	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 6		# - 2 pixels

  			
nextByte:
	
	add $t6, $t5, $t3
	lbu $s4, ($t6)
	mul $s4, $s4, $s1 	# middle left 
	move $s5, $s4
	
	lbu $s4, 3($t6)
	mul $s4, $s4, $s0	# center
	add $s5, $s5, $s4
	
	lbu $s4, 6($t6)
	mul $s4, $s4, $s1	# middle right
	add $s5, $s5, $s4
	
	#######################
	
	sub $t3, $t3, $s3
	
	add $t6, $t5, $t3
	lbu $s4, ($t6)
	mul $s4, $s4, $s2 	# bottom left
	add $s5, $s5, $s4
	
	lbu $s4, 3($t6)
	mul $s4, $s4, $s1	# bottom center
	add $s5, $s5, $s4
	
	lbu $s4, 6($t6)
	mul $s4, $s4, $s2	# bottom right
	add $s5, $s5, $s4
	
	#######################
	
	add $t3, $t3, $s3
	add $t3, $t3, $s3
	
	add $t6, $t5, $t3
	lbu $s4, ($t6)
	mul $s4, $s4, $s2 	# top left
	add $s5, $s5, $s4
	
	lbu $s4, 3($t6)
	mul $s4, $s4, $s1	# top center
	add $s5, $s5, $s4
	
	lbu $s4, 6($t6)
	mul $s4, $s4, $s2	# top right
	add $s5, $s5, $s4
	
	#######################
	
	# Calculate new blue value:
	div $s5, $s6		
	mflo $s4		
	
	# Store this value in outbuffer:
	sub $t3, $t3, $s3
	add $t6, $t7, $t3
	sb $s4, 3($t6)
	
	
	# Increment pixel
	add $t3, $t3, 1
	blt $t3, $t4, nextByte
	
	# Increment row
	add  $t3, $t3, $t9  
	addi $t3, $t3, 6
	blt  $t3, $t8, nextRow
	
	
	
	# Write header to output file:
	lw $t8, size
	
	move $a0, $t1        # output file descriptor 
	move $a1, $t7	     # address of buffer from which to write
	move $a2, $t8        # buffer length
	li   $v0, 15         # write to file
	syscall
	
exit:	
	# Close opened files:
	move $a0, $t0      # input file descriptor to close
	li   $v0, 16       # close file 
	syscall
	
	move $a0, $t1      # output file descriptor to close
	li   $v0, 16       # close file 
	syscall            
	
	# Exit program:
	li $v0, 10
	syscall

	
fileError:
	la $a0, errorMsg 	# Error opening file message
	li $v0, 4
	syscall
	
	b exit
