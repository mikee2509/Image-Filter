.data

.eqv CENTER_FACTOR  1
.eqv EDGE_FACTOR    1
.eqv CORNER_FACTOR  1
.eqv BUFFER_SIZE	9000
		
header:		.space 56
buffer:		.space BUFFER_SIZE
buffer2:	.space BUFFER_SIZE
outbuffer:	.space BUFFER_SIZE
size:		.space 4

welcomeMsg:		.asciiz "High Pass / Low Pass filter\n   Michal Sieczkowski 04.2017\n\n"
openedMsg:		.asciiz "File opened\n"
fileErrorMsg:	.asciiz "Error opening/reading file\n"
headerErrorMsg:	.asciiz "Error in file header\n"
inFileName:		.asciiz "image.bmp"
outFileName:	.asciiz "image_out.bmp"

widthMsg: 		.asciiz "Width: "
heightMsg: 		.asciiz "\nHeight: "
sizeMsg:		.asciiz "\nSize: "
newLineMsg:		.asciiz "\n"


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
	li $a1, 0			# open for reading only
	li $a2, 0			# mode is ignored
	li $v0, 13			# open file
	syscall

	move $t0, $v0 		# save file descriptor in $t0 (negative if error)
	bltz $t0, fileError	# exit program if error occured
	
	
	# Open output file for writing:
	la $a0, outFileName	# file name
	li $a1, 1			# open for writing
	li $a2, 0			# mode is ignored
	li $v0, 13			# open file
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
  	move $a0, $t0     	  # input file descriptor
	la   $a1, header+2    # input buffer address
  	li   $a2, 54		  # num of characters to read
  	li   $v0, 14  	 	  # read from file
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
	
	# Print image width
	la $a0, widthMsg 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s1
	syscall
	
	# Print image height
	la $a0, heightMsg 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s2
	syscall
	
	# Print bitmap size in bytes
	la $a0, sizeMsg 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s0
	syscall
	
	# Print new line
	la $a0, newLineMsg 	
	li $v0, 4
	syscall


	
	# ---------- Calculate row size -----------------------
	# The formula is:	
	# floor((24*width + 31) / 32) * 4
	#
	# [temp] $s1 - width in pixels
	# -----------------------------------------------------
	mul $s0, $s1, 24
	addi $s0, $s0, 31	
	li $s2, 32
	div $s0, $s2		# Floor is achieved by taking the quotient of division
	mflo $s0
	mul $t8, $s0, 4		# $t8 holds row size from now on
	
	
	# ---------- Calculate padding ------------------------
	# padding = row_size - (width * 3)
	# -----------------------------------------------------
	mul $s0, $s1, 3		
	sub $t9, $t8, $s0	 # $t9 holds padding from now on


	# Write header to output file:
	move $a0, $t1        # output file descriptor 
	la   $a1, header+2   # address of buffer from which to write
	li   $a2, 54         # header length
	li   $v0, 15         # write to file
	syscall
	
	
	
	# ------------------------  Bitmap processing  ----------------------------------
	# Filter mask:
	#  | CORNER |  EDGE  | CORNER |
	#  |  EDGE  | CENTER |  EDGE  |
	#  | CORNER |  EDGE  | CORNER |
	#
	# $s0 - size of bitmap in bytes
	# $s1 - temp
	# $s2 - currently used buffer
	# $s3 - sum of factors
	# $s4 - value of single byte of pixel in mask
	# $s5 - sum of bytes in mask multiplied by their factors
	# $s6 - number of bytes to read
	# $s7 - number of bytes read
	#
	# $t2 - number of bytes read overall
	# $t3 - current byte of bitmap
	# $t4 - end of inner row position (a)
	# $t5 - end of middle rows position (b) / temp in transition 
	# $t6 - start of inner row position (c) / start of padding bytes position (d)
	# $t7 - read state
	#
	# Read states:
	#  $t7 = 0  -  nothing read yet
	#  $t7 = 1  -  the last block of bitmap read
	#  $t7 = 2  -  more blocks expected
	#
	# Example bitmap:
	#   bitmap_size = 80B
	#   image_width = 6pix = 18B
	#   row_size = 20B
	#   padding = 2B
	#
	#	|b. . | . . | . . | . . | . . | . . | . |
	#	| . . | . . | . . | . . | . . | . . | . |
	#	| . . |c. . | . . | . . | . . |a. . |d. |
	#	| . . | . . | . . | . . | . . | . . | . |
	#
	#--------------------------------------------------------------------------------
	

	# Calculate sum of factors
	li $s1, EDGE_FACTOR
	mul $s3, $s1, 4
	li $s1, CORNER_FACTOR
	mul $s2, $s1, 4		
	add $s3, $s3, $s2
	add $s3, $s3, CENTER_FACTOR

	

	# --- Calculate the number of rows that fit into buffer multiplied by row_size ---
  	# The formula is:
  	# (floor(BUFFER_SIZE / row_size))*row_size
  	# --------------------------------------------------------------------------------
	li $s1, BUFFER_SIZE 	# s1 - temp
	div $s1, $t8		
	mflo $s6				# Floor is achieved by taking the quotient of division
	mul $s6, $s6, $t8


	# Make sure $t2 and $t7 are zero
	move $t2, $zero
	move $t7, $zero

	# Load bitmap size
	lw  $s0, size

	#Set current buffer
	la $s2, buffer

readFirstBlockToBuffer:
	# Read to buffer:
  	move $a0, $t0     			# input file descriptor
	move $a1, $s2   			# input buffer address
  	move $a2, $s6				# max num of characters to read
  	li   $v0, 14  	 			# read from file
  	syscall
  	move $s7, $v0				# $v0 contains number of characters read (0 if end-of-file, negative if error)
  	bltz $s7, fileError


  	# Advance the total-bytes-read counter
  	add $t2, $t2, $s7

  	# Calculate end of middle rows position
	sub $t5, $s7, $t8	# $t5 = bytes_read - row_size
	move $t3, $zero		# $t3 - current position (now: 1st pixel in 1st row)

  	# If the number of bytes read equal bitmap size, the first and only block of bitmap was read
  	beq $s7, $s0, oneBlockBitmap

multiBlockBitmap:
	li $t7, 2
	b bottomEdgeInit

oneBlockBitmap:
	li $t7, 1

bottomEdgeInit:
	#Calculate start of inner row position
	add $t6, $t3, 3

  	#Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

bottomLeftCornerPixel:
	##### START FILTERING #####

	lbu $s4, buffer($t3)
	mul $s4, $s4, EDGE_FACTOR 	# middle left = center
	move $s5, $s4
	add $s5, $s5, $s4			# bottom center = center

	lbu $s4, buffer($t3)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, CORNER_FACTOR	# bottom left = center
	add $s5, $s5, $s4

	lbu $s4, buffer+3($t3)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4

	lbu $s4, buffer+3($t3)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = middle right
	add $s5, $s5, $s4
	
	############################	
	add $t3, $t3, $t8
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, CORNER_FACTOR 	# top left = top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next left edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, bottomLeftCornerPixel

	# Calculate start of padding position
	add $t6, $t4, 3

bottomEdgeMiddlePixels:
	##### START FILTERING #####

	sub $t3, $t3, 3

	lbu $s4, buffer($t3)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4

	lbu $s4, buffer($t3)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left = middle left
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4

	lbu $s4, buffer+3($t3)
	mul $s4, $s4, EDGE_FACTOR	# bottom center = center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+6($t3)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4

	lbu $s4, buffer+6($t3)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = middle right
	add $s5, $s5, $s4

	############################
	
	add $t3, $t3, $t8
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+6($t3)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, bottomEdgeMiddlePixels

bottomRightCornerPixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	lbu $s4, buffer($t3)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4

	lbu $s4, buffer($t3)
	mul $s4, $s4, CORNER_FACTOR # bottom left = middle left 
	add $s5, $s5, $s4

	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, EDGE_FACTOR	# middle right = center
	add $s5, $s5, $s4
	add $s5, $s5, $s4			# bottom center = center

	lbu $s4, buffer+3($t3)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = center
	add $s5, $s5, $s4

	############################
	
	add $t3, $t3, $t8
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, CORNER_FACTOR	# top right = top center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, bottomRightCornerPixel

	## Increment row
	add  $t3, $t3, $t9  # advance current position by the number of padding bytes
	
nextRow:
	#Calculate start of inner row position
	add $t6, $t3, 3

  	#Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

leftEdgePixel:
	##### START FILTERING #####

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left = center
	move $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4
	
	############################
	
	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################
	
	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left = top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next left edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, leftEdgePixel

	# Calculate start of padding position
	add $t6, $t4, 3

middlePixels:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4
	
	############################

	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################
	
	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, middlePixels

rightEdgePixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right = center
	add $s5, $s5, $s4
	
	############################
	
	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = bottom center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################

	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = top center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, rightEdgePixel


incrementRow:
	## Increment row
	add  $t3, $t3, $t9  	# advance current position by the number of padding bytes
	blt  $t3, $t5, nextRow	# if current position is less than 'end of middle rows' position process the next row


	# If it is the last block of bitmap, process the last row
	beq $t7, 1, topEdgeInit


transitionToTheNextBlock:
	la $s1, buffer
	beq $s2, $s1, changeToBuffer2

changeToBuffer:
	la $s2, buffer
	la $s1, buffer2
	b readNextBlockToBuffer

changeToBuffer2:
	la $s2, buffer2
	la $s1, buffer

readNextBlockToBuffer:
	# Read to buffer:
  	move $a0, $t0     		# input file descriptor
	move $a1, $s2   		# input buffer address
  	move $a2, $s6			# max num of characters to read
  	li   $v0, 14  	 		# read from file
  	syscall
  	move $s7, $v0			# $v0 contains number of characters read (0 if end-of-file, negative if error)
  	bltz $s7, fileError

  	# Advance the total bytes read counter
  	add $t2, $t2, $s7

  	# If (bitmap_size - number of bytes read overall) is less or equal to the 'number 
  	# of bytes to read to the buffer' we have read the last block
  	sub $t5, $s0, $t2
  	add $t5, $t5, $s6
  	ble $t5, $s6, changeState

  	b lastRowInit

changeState:
	li $t7, 1

lastRowInit:
	#Calculate start of inner row position
	add $t6, $t3, 3

  	#Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

  	#Save the start of last row position
  	move $t5, $t3

lastRowLeftEdgePixel:
	##### START FILTERING #####

	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left = center
	move $s5, $s4
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4
	
	############################

	sub $t3, $t3, $t8
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################

	sub $t3, $t3, $t5
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left = top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t5

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next left edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, lastRowLeftEdgePixel

	# Calculate start of padding position
	add $t6, $t4, 3
	
lastRowMiddlePixels:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4
	
	############################	

	sub $t3, $t3, $t8
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################

	sub $t3, $t3, $t5

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t5

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, lastRowMiddlePixels

lastRowRightEdgePixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right = center
	add $s5, $s5, $s4
	
	############################

	sub $t3, $t3, $t8
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = bottom center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################

	sub $t3, $t3, $t5
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = top center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t5

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, lastRowRightEdgePixel


writeToFile2:
	# Write bitmap to output file:
	move $a0, $t1        	 	# output file descriptor 
	la   $a1, outbuffer	 		# address of buffer from which to write
	move $a2, $s6		 	 	# buffer length
	li   $v0, 15				# write to file
	syscall	


firstRowInit:
	move $t3, $zero

	#Calculate start of inner row position
	add $t6, $t3, 3

  	#Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

firstRowLeftEdgePixel:
	##### START FILTERING #####

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left = center
	move $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4
	
	############################

	add $t3, $t3, $t5
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t5

	############################	

	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left = top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next left edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, firstRowLeftEdgePixel

	# Calculate start of padding position
	add $t6, $t4, 3
	
firstRowMiddlePixels:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4
	
	############################	

	add $t3, $t3, $t5
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t5

	############################

	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####
	
	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, firstRowMiddlePixels

firstRowRightEdgePixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right = center
	add $s5, $s5, $s4
	
	############################

	add $t3, $t3, $t5
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = bottom center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t5

	############################	

	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = top center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, firstRowRightEdgePixel


processMiddleRowsOfNewBlock:
	# Increment row
	add  $t3, $t3, $t9  		# advance current position by the number of padding bytes

	#Calculate the new 'end of middle rows position'
	sub $t5, $s7, $t8	# $t5 = bytes_read - row_size

	blt  $t3, $t5, nextRow		# if current position is less than 'end of middle rows' position process the next row


topEdgeInit:
	# Calculate start of inner row position
	add $t6, $t3, 3

  	# Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

topLeftCornerPixel:
	##### START FILTERING #####

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left = center
	move $s5, $s4
	add $s5, $s5, $s4			# top center = center

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top left = center
	add $s5, $s5, $s4

	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4

	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = middle right
	add $s5, $s5, $s4
	
	############################

	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next left edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, topLeftCornerPixel

	# Calculate start of padding position
	add $t6, $t4, 3

topEdgeMiddlePixels:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left = middle left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4

	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center = center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4

	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = middle right
	add $s5, $s5, $s4

	############################

	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR # bottom left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, topEdgeMiddlePixels

topRightCornerPixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR # top left = middle left 
	add $s5, $s5, $s4

	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right = center
	add $s5, $s5, $s4
	add $s5, $s5, $s4			# top center = center

	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = center
	add $s5, $s5, $s4

	############################

	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = bottom center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, topRightCornerPixel

	## Increment row
	add  $t3, $t3, $t9  	# advance current position by the number of padding bytes


writeToFile:
	# Write bitmap to output file:
	move $a0, $t1        	 	# output file descriptor 
	la   $a1, outbuffer	 		# address of buffer from which to write
	move $a2, $s7		 	 	# buffer length
	li   $v0, 15				# write to file
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
