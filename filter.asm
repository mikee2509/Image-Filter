.data

.eqv BUFFER_SIZE	9000
		
header:			.space 56
buffer:			.space BUFFER_SIZE
buffer2:		.space BUFFER_SIZE
outbuffer:		.space BUFFER_SIZE
size:			.space 4
inFileDesc:		.space 4
outFileDesc:	.space 4
inputPath:		.space 80
outputPath:	 	.space 80
readOverall:	.space 4

msgWelcome:		.asciiz "High Pass / Low Pass filter\n   Michal Sieczkowski 04.2017\n\n"
msgInput:		.asciiz "Input file: "
msgOutput:		.asciiz "Output file: "
msgOpened:		.asciiz "Files opened successfully!\n\n"
msgFileError:	.asciiz "Error opening/reading file\n"
msgHeaderError:	.asciiz "Error in file header\n"
msgCenter:		.asciiz "Center factor: "
msgEdge:		.asciiz "Edge factor: "
msgCorner:		.asciiz "Corner factor: "
msgWidth: 		.asciiz "Width: "
msgHeight: 		.asciiz "\nHeight: "
msgSize:		.asciiz "\nSize: "
msgNewLine:		.asciiz "\n"


.text
.globl main

main:
	# Welcome message:
	la $a0, msgWelcome
	li $v0, 4
	syscall


	# --------------------------  Reading file paths  ---------------------------

getInputPath:
	# Print message
	li $v0, 4	
	la $a0, msgInput  
	syscall
	# Get path
	li $v0, 8 	
	la $a0, inputPath 
	li $a1, 80 
	syscall
	# Copy path address
	move $s0, $a0

loopFixInputPath:
	lb $t0, ($a0)
	beq $t0, 0xA, delNewlineInputPath
	addi $a0, $a0, 1
	b loopFixInputPath
	
delNewlineInputPath:
	sb $zero, ($a0) 
	
getOutputPath:
	# Print message
	li $v0, 4	
	la $a0, msgOutput  
	syscall
	# Get path
	li $v0, 8 	
	la $a0, outputPath 
	li $a1, 80 
	syscall
	# Copy path address
	add $s1, $a0, $zero
	
loopFixOutputPath:
	lb $t0, ($a0)
	beq $t0, 0xA, delNewlineOutputPath
	addi $a0, $a0, 1
	b loopFixOutputPath
	
delNewlineOutputPath:
	sb $zero, ($a0) 
	
	
	# ----------------------------  Opening files  -----------------------------
	# $t0 - input file descriptor
	# $t1 - output file descriptor
	# --------------------------------------------------------------------------
	
	# Open input file for reading:
	la $a0, inputPath	# file name
	li $a1, 0			# open for reading only
	li $a2, 0			# mode is ignored
	li $v0, 13			# open file
	syscall

	move $t0, $v0 		# save file descriptor in $t0 (negative if error)
	bltz $t0, fileError	# exit program if error occured
	
	
	# Open output file for writing:
	la $a0, outputPath	# file name
	li $a1, 1			# open for writing
	li $a2, 0			# mode is ignored
	li $v0, 13			# open file
	syscall
	
	move $t1, $v0 		# save file descriptor in $t1 (negative if error)
	bltz $t1, fileError	# exit program if error occured
	
	
	# Success opening files message:
	la $a0, msgOpened
	li $v0, 4
	syscall
	

	# --------------------------  Reading factors  -----------------------------
	# $s3 - center factor
	# $s4 - edge factor
	# $s5 - corner factor
	# --------------------------------------------------------------------------


	# Print message
	li $v0, 4	
	la $a0, msgCenter 
	syscall
	# Read center factor
	li $v0, 5
	syscall
	move $s3, $v0

	# Print message
	li $v0, 4	
	la $a0, msgEdge 
	syscall
	# Read edge factor
	li $v0, 5
	syscall
	move $s4, $v0

	# Print message
	li $v0, 4	
	la $a0, msgCorner 
	syscall
	# Read corner factor
	li $v0, 5
	syscall
	move $s5, $v0
	

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
	la $a0, msgWidth 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s1
	syscall
	
	# Print image height
	la $a0, msgHeight 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s2
	syscall
	
	# Print bitmap size in bytes
	la $a0, msgSize 	
	li $v0, 4
	syscall
	li $v0, 1
	move $a0, $s0
	syscall
	
	# Print new line
	la $a0, msgNewLine 	
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


	# Save file descriptors
	sw $t0, inFileDesc
	sw $t1, outFileDesc

	# Move factors to new registers
	move $t0, $s3
	move $t1, $s4
	move $t2, $s5
	
	# ------------------------  Bitmap processing  ----------------------------------
	# Filter mask:
	#  | $t2 | $t1 | $t2 |
	#  | $t1 | #t0 | $t1 |
	#  | $t2 | $t1 | $t2 |
	#
	# $s0 - size of bitmap in bytes
	# $s1 - temp / currently used buffer
	# $s2 - currently used buffer
	# $s3 - sum of factors
	# $s4 - value of single byte of pixel in mask
	# $s5 - sum of bytes in mask multiplied by their factors
	# $s6 - number of bytes to read
	# $s7 - number of bytes read
	#
	# $t0 - center factor
	# $t1 - edge factor
	# $t2 - corner factor
	#
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
	move $s1, $t1
	mul  $s3, $s1, 4
	move $s1, $t2
	mul  $s2, $s1, 4		
	add  $s3, $s3, $s2
	add  $s3, $s3, $t0

	

	# --- Calculate the number of rows that fit into buffer multiplied by row_size ---
  	# The formula is:
  	# (floor(BUFFER_SIZE / row_size))*row_size
  	# --------------------------------------------------------------------------------
	li $s1, BUFFER_SIZE 	# s1 - temp
	div $s1, $t8		
	mflo $s6				# Floor is achieved by taking the quotient of division
	mul $s6, $s6, $t8


	# Make sure readOverall and $t7 are zero
	sw $zero, readOverall
	move $t7, $zero

	# Load bitmap size
	lw  $s0, size

	#Set current buffer
	la $s2, buffer

readFirstBlockToBuffer:
	# Read to buffer:
  	lw 	 $a0, inFileDesc		# input file descriptor
	move $a1, $s2   			# input buffer address
  	move $a2, $s6				# max num of characters to read
  	li   $v0, 14  	 			# read from file
  	syscall
  	move $s7, $v0				# $v0 contains number of characters read (0 if end-of-file, negative if error)
  	bltz $s7, fileError


  	# Advance the total-bytes-read counter
  	lw $s4, readOverall
  	add $s4, $s4, $s7
  	sw $s4, readOverall

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
	jal rowProcessingInit

bottomLeftCornerPixel:
	##### START FILTERING #####

	lbu $s4, buffer($t3)
	mul $s4, $s4, $t1 	# middle left = center
	move $s5, $s4
	add $s5, $s5, $s4			# bottom center = center

	lbu $s4, buffer($t3)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, $t2	# bottom left = center
	add $s5, $s5, $s4

	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4

	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t2	# bottom right = middle right
	add $s5, $s5, $s4
	
	############################	
	add $t3, $t3, $t8
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, $t2 	# top left = top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t2	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
	# Go to the next left edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, bottomLeftCornerPixel

	# Calculate start of padding position
	add $t6, $t4, 3

bottomEdgeMiddlePixels:
	##### START FILTERING #####

	sub $t3, $t3, 3

	lbu $s4, buffer($t3)
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4

	lbu $s4, buffer($t3)
	mul $s4, $s4, $t2 	# bottom left = middle left
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4

	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t1	# bottom center = center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+6($t3)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4

	lbu $s4, buffer+6($t3)
	mul $s4, $s4, $t2	# bottom right = middle right
	add $s5, $s5, $s4

	############################
	
	add $t3, $t3, $t8
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, $t2 	# top left
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+6($t3)
	mul $s4, $s4, $t2	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, bottomEdgeMiddlePixels

bottomRightCornerPixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	lbu $s4, buffer($t3)
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4

	lbu $s4, buffer($t3)
	mul $s4, $s4, $t2 # bottom left = middle left 
	add $s5, $s5, $s4

	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t1	# middle right = center
	add $s5, $s5, $s4
	add $s5, $s5, $s4			# bottom center = center

	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t2	# bottom right = center
	add $s5, $s5, $s4

	############################
	
	add $t3, $t3, $t8
	
	lbu $s4, buffer($t3)
	mul $s4, $s4, $t2 	# top left
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	lbu $s4, buffer+3($t3)
	mul $s4, $s4, $t2	# top right = top center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, bottomRightCornerPixel

	## Increment row
	add  $t3, $t3, $t9  # advance current position by the number of padding bytes
	
nextRow:
	jal rowProcessingInit

leftEdgePixel:
	##### START FILTERING #####

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1 	# middle left = center
	move $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4
	
	############################
	
	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################
	
	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left = top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
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
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4
	
	############################

	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################
	
	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, middlePixels

rightEdgePixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right = center
	add $s5, $s5, $s4
	
	############################
	
	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right = bottom center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################

	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right = top center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
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
  	lw $a0, inFileDesc     	# input file descriptor
	move $a1, $s2   		# input buffer address
  	move $a2, $s6			# max num of characters to read
  	li   $v0, 14  	 		# read from file
  	syscall
  	move $s7, $v0			# $v0 contains number of characters read (0 if end-of-file, negative if error)
  	bltz $s7, fileError

  	# Advance the total bytes read counter
  	lw $s4, readOverall
  	add $s4, $s4, $s7
  	sw $s4, readOverall
  	
  	# If (bitmap_size - number of bytes read overall) is less or equal to the 'number 
  	# of bytes to read to the buffer' we have read the last block
  	sub $t5, $s0, $s4
  	add $t5, $t5, $s6
  	ble $t5, $s6, changeState

  	b lastRowInit

changeState:
	li $t7, 1

lastRowInit:
	jal rowProcessingInit

  	#Save the start of last row position
  	move $t5, $t3

lastRowLeftEdgePixel:
	##### START FILTERING #####

	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1 	# middle left = center
	move $s5, $s4
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4
	
	############################

	sub $t3, $t3, $t8
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################

	sub $t3, $t3, $t5
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left = top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t5

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
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
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4
	
	############################	

	sub $t3, $t3, $t8
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################

	sub $t3, $t3, $t5

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t5

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, lastRowMiddlePixels

lastRowRightEdgePixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right = center
	add $s5, $s5, $s4
	
	############################

	sub $t3, $t3, $t8
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right = bottom center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	############################

	sub $t3, $t3, $t5
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right = top center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t5

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, lastRowRightEdgePixel


writeToFile2:
	# Write bitmap to output file:
	lw   $a0, outFileDesc		# output file descriptor 
	la   $a1, outbuffer	 		# address of buffer from which to write
	move $a2, $s6		 	 	# buffer length
	li   $v0, 15				# write to file
	syscall	


firstRowInit:
	move $t3, $zero

	jal rowProcessingInit

firstRowLeftEdgePixel:
	##### START FILTERING #####

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1 	# middle left = center
	move $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4
	
	############################

	add $t3, $t3, $t5
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t5

	############################	

	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left = top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
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
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4
	
	############################	

	add $t3, $t3, $t5
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t5

	############################

	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####
	
	jal calculateNewValueAndStore
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, firstRowMiddlePixels

firstRowRightEdgePixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right = center
	add $s5, $s5, $s4
	
	############################

	add $t3, $t3, $t5
	
	add $s4, $s1, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s1, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right = bottom center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t5

	############################	

	add $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right = top center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
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
	mul $s4, $s4, $t1 	# middle left = center
	move $s5, $s4
	add $s5, $s5, $s4			# top center = center

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top left = center
	add $s5, $s5, $s4

	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4

	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right = middle right
	add $s5, $s5, $s4
	
	############################

	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
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
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# top left = middle left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4

	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# top center = center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right
	add $s5, $s5, $s4

	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right = middle right
	add $s5, $s5, $s4

	############################

	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 # bottom left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, topEdgeMiddlePixels

topRightCornerPixel:
	##### START FILTERING #####

	sub $t3, $t3, 3

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1 	# middle left 
	move $s5, $s4

	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 # top left = middle left 
	add $s5, $s5, $s4

	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t0	# center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# middle right = center
	add $s5, $s5, $s4
	add $s5, $s5, $s4			# top center = center

	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# top right = center
	add $s5, $s5, $s4

	############################

	sub $t3, $t3, $t8
	
	add $s4, $s2, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t1	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $s2, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, $t2	# bottom right = bottom center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	add $t3, $t3, 3

	##### END OF FILTERING #####

	jal calculateNewValueAndStore
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, topRightCornerPixel

	## Increment row
	add  $t3, $t3, $t9  	# advance current position by the number of padding bytes


writeToFile:
	# Write bitmap to output file:
	lw   $a0, outFileDesc  	 	# output file descriptor 
	la   $a1, outbuffer	 		# address of buffer from which to write
	move $a2, $s7		 	 	# buffer length
	li   $v0, 15				# write to file
	syscall
	
exit:	
	# Close opened files:
	lw $a0, inFileDesc    # input file descriptor to close
	li $v0, 16       	  # close file 
	syscall
	
	lw $a0, outFileDesc   # output file descriptor to close
	li $v0, 16       	  # close file 
	syscall            
	
	# Exit program:
	li $v0, 10
	syscall

	
fileError:
	la $a0, msgFileError 	# Error opening file message
	li $v0, 4
	syscall
	
	b exit
	
headerError:
	la $a0, msgHeaderError 	# Error opening file message
	li $v0, 4
	syscall
	
	b exit

	
calculateNewValueAndStore:
	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4

	# Check pixel's byte value
	li $s5, 255
	bgt $s4, $s5, outOfBounds
	li $s5, 0
	blt $s4, $s5, outOfBounds

	# Store value in outbuffer:
	sb $s4, outbuffer($t3)
	jr $ra

	outOfBounds:
	sb $s5, outbuffer($t3)
	jr $ra


rowProcessingInit:
	#Calculate start of inner row position
	add $t6, $t3, 3

  	#Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

  	jr $ra


