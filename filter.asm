.data
	.eqv CENTER_FACTOR  2
	.eqv EDGE_FACTOR    1
	.eqv CORNER_FACTOR  1
		
header:		.space 56
buffer:		.space 9000
outbuffer:	.space 9000
size:		.space 4  # space for input image bitmap size in bytes
width:		.space 4  # space for image width in pixels
height:		.space 4  # space for image height in pixels

welcomeMsg:	.asciiz "High Pass / Low Pass filter\n   Michal Sieczkowski 04.2017\n\n"
openedMsg:	.asciiz "File opened\n"
fileErrorMsg:	.asciiz "Error opening/reading file\n"
headerErrorMsg:	.asciiz "Error in file header\n"
inFileName:	.asciiz "jacht.bmp"
outFileName:	.asciiz "jacht_out.bmp"


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
	
	
	# ----------------------------  Opening files  -----------------------------
	# $t0 - input file descriptor
	# $t1 - output file descriptor
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
	
	
	
	# ------------------------  Header processing  -----------------------------
	# $t8 - row size
	# $t9 - padding
	#---------------------------------------------------------------------------
	
	# Reading the header from file
  	move $a0, $t0     	# input file descriptor
	la   $a1, header+2   	# input buffer address
  	li   $a2, 54		# num of characters to read
  	li   $v0, 14  	 	# read from file
  	syscall			
  	
  	# Check the first 2 bytes
  	lb $s0, header+2
  	lb $s1, header+3
  	bne $s0, 'B', headerError
  	bne $s1, 'M', headerError
  	
  	# Check offset - starting address of the bitmap
  	lw $s0, header+12
  	bne $s0, 54, headerError
  	
  	# Check header size
  	lw $s0, header+16
  	bne $s0, 40, headerError
  	
  	# Check bits per pixel
  	lh $s0, header+30
  	bne $s0, 24, headerError
  	
  	# Load image size, width and height
	lw $s0, header+4	# load file size
	lw $s1, header+20	# load image width
	lw $s2, header+24	# load image height
	
	sub $s0, $s0, 54
	sw  $s0, size		# store image bitmap size
	sw  $s1, width		# store image width
	sw  $s2, height		# store image height
	
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
##---------------------------------------
	
	# ---------- Calculate row size ----------
	# The formula is:	
	# floor((24*width + 31) / 32) * 4
	#
	# [temp] $s1 - width in pixels
	# ----------------------------------------
	mul $s0, $s1, 24
	addi $s0, $s0, 31	
	li $s2, 32
	div $s0, $s2		# Floor is achived by taking the quotient of division
	mflo $s0
	mul $t8, $s0, 4		# $t8 holds row size from now on
	
	
	# ---------- Calculate padding -----------
	# padding = row_size - (width * 3)
	# ----------------------------------------
	mul $s0, $s1, 3		
	sub $t9, $t8, $s0	# $t9 holds padding from now on


	# Write header to output file:
	move $a0, $t1        # output file descriptor 
	la   $a1, header+2   # address of buffer from which to write
	li   $a2, 54         # header length
	li   $v0, 15         # write to file
	syscall
	
	
	
	# ------------------------  Bitmap processing  -----------------------------
	# Filter window:
	#  |s2|s1|s2|
	#  |s1|s0|s1|
	#  |s2|s1|s2|
	#
	# $s0 - center factor
	# $s1 - edge factor
	# $s2 - corner facotr
	#---------------------------------------------------------------------------
	
	li $s0, CENTER_FACTOR
	li $s1, EDGE_FACTOR
	li $s2, CORNER_FACTOR
	mul $s6, $s1, 4
	mul $s7, $s2, 4
	add $s6, $s6, $s7
	add $s6, $s6, $s0  # sum of factors 
	
	
readToBuffer:
	# Read to buffer:
  	move $a0, $t0     	# input file descriptor
	la   $a1, buffer   	# input buffer address
  	li   $a2, 9000		# max num of characters to read
  	li   $v0, 14  	 	# read from file
  	syscall	
  	move $t2, $v0		
  	bltz $t2, fileError
  	
  	# ok wczytałem t2 bajtów potem sprawdze czy to tyle (t2<9000) czy trzeba jeszcze, 
  	# processuje pierwszys rząd
  
  
  	move $t3, $t8
	lw $t7, size
	sub $t7, $t7, $t8
  	
nextRow:
  	#End of row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 6		# - 2 pixels

  			
nextByte:
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, $s1 	# middle left 
	move $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $s0	# center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+6($t3)
	mul $s4, $s4, $s1	# middle right
	add $s5, $s5, $s4
	
	#######################
	
	sub $t3, $t3, $t8
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, $s2 	# bottom left
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $s1	# bottom center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+6($t3)
	mul $s4, $s4, $s2	# bottom right
	add $s5, $s5, $s4
	
	#######################
	
	add $t3, $t3, $t8
	add $t3, $t3, $t8
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, $s2 	# top left
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $s1	# top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+6($t3)
	mul $s4, $s4, $s2	# top right
	add $s5, $s5, $s4
	
	#######################
	
	# Calculate new blue value:
	div $s5, $s6		
	mflo $s4		
	
	# Store this value in outbuffer:
	sub $t3, $t3, $t8
	sb $s4, outbuffer+3($t3)
	
	
	# Increment pixel
	add $t3, $t3, 1
	blt $t3, $t4, nextByte
	
	# Increment row
	add  $t3, $t3, $t9  
	addi $t3, $t3, 6
	blt  $t3, $t7, nextRow
	
	
	
	# Write header to output file:
	move $a0, $t1        # output file descriptor 
	la   $a1, outbuffer  # address of buffer from which to write
	li   $a2, 9000       # buffer length
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
	la $a0, fileErrorMsg 	# Error opening file message
	li $v0, 4
	syscall
	
	b exit
	
headerError:
	la $a0, headerErrorMsg 	# Error opening file message
	li $v0, 4
	syscall
	
	b exit
