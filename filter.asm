.data
	.eqv CENTER_FACTOR  4
	.eqv EDGE_FACTOR    2
	.eqv CORNER_FACTOR  1
	.eqv BUFFER_SIZE	9000
		
header:		.space 56
buffer:		.space BUFFER_SIZE
buffer2:	.space BUFFER_SIZE
outbuffer:	.space BUFFER_SIZE
size:		.space 4  				# space for input image bitmap size in bytes
width:		.space 4  				# space for image width in pixels
height:		.space 4  				# space for image height in pixels

welcomeMsg:		.asciiz "High Pass / Low Pass filter\n   Michal Sieczkowski 04.2017\n\n"
openedMsg:		.asciiz "File opened\n"
fileErrorMsg:	.asciiz "Error opening/reading file\n"
headerErrorMsg:	.asciiz "Error in file header\n"
inFileName:		.asciiz "jacht.bmp"
outFileName:	.asciiz "jacht_out.bmp"


debugWidth: 	.asciiz "Width: "
debugHeight: 	.asciiz "\nHeight: "
debugSize:		.asciiz "\nSize: "
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
	li $a1, 0			# open for reading only
	li $a2, 0			# mode is ignored
	li $v0, 13			# open file
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
	div $s0, $s2		# Floor is achieved by taking the quotient of division
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
	# Filter mask:
	#  | CORNER |  EDGE  | CORNER |
	#  |  EDGE  | CENTER |  EDGE  |
	#  | CORNER |  EDGE  | CORNER |
	#
	# $s3 - sum of factors
	# $s4 - value of single byte of pixel in mask
	# $s5 - sum of bytes in mask multiplied by their factors 
	#
	# $t2 - number of bytes read overall
	# $t3 - current byte of bitmap
	# $t4 - end of inner row position (a)
	# $t5 - end of middle rows position (b)
	# $t6 - start of inner row position (c) / start of padding bytes position (d)
	# $t7 - current buffer address
	#
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
	#---------------------------------------------------------------------------
	
	# Calculate sum of factors
	li $s1, EDGE_FACTOR
	mul $s3, $s1, 4
	li $s1, CORNER_FACTOR
	mul $s2, $s1, 4		
	add $s3, $s3, $s2
	add $s3, $s3, CENTER_FACTOR

	# Set current buffer register
	la $t7, buffer

	# Make sure $t2 is zero
	move $t2, $zero

readToBuffer:
	# Read to buffer:
  	move $a0, $t0     			# input file descriptor
	move $a1, $t7   			# input buffer address
  	li   $a2, BUFFER_SIZE		# max num of characters to read
  	li   $v0, 14  	 			# read from file
  	syscall
  	move $t5, $v0				# $v0 contains number of characters read (0 if end-of-file, negative if error)
  	bltz $t5, fileError

  	add $t2, $t2, $t5	# add to the total of read bytes of bitmap

  	move $t3, $zero		# $t3 - current position (now: 1st pixel in 1st row)
  	
  	blt $t5, BUFFER_SIZE, lastBlock	# if less than BUFFER_SIZE bytes were read, the last block of bitmap is being processed


  	# --- Calculate the 'end of middle rows' position for this block ---
  	# The formula is:
  	# (floor(BUFFER_SIZE / row_size)-1)*row_size
  	# ------------------------------------------------------------------
	li $s6, BUFFER_SIZE 		# s6 - temp
	div $s6, $t8		
	mflo $t5			# Floor is achieved by taking the quotient of division
	sub $t5, $t5, 1
	mul $t5, $t5, $t8

	b nextRow

lastBlock:
	sub $t5, $t5, $t8	# $t5 = bitmap_size - row_size

firstRowInit:
	#Calculate start of inner row position
	add $t6, $t3, 3

  	#Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

firstRowLeftEdgePixel:
	##### START ##########

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left = center
	move $s5, $s4
	add $s5, $s5, $s4			# bottom center = center

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom left = center
	add $s5, $s5, $s4

	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4

	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = middle right
	add $s5, $s5, $s4
	
	#######################
	
	add $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left = top center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	###### END ############

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
	##### START ##########
	sub $t3, $t3, 3

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left = middle left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4

	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center = center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4

	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = middle right
	add $s5, $s5, $s4

	#######################
	
	add $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	###### END ############

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, firstRowMiddlePixels

firstRowRightEdgePixel:
	##### START ##########
	sub $t3, $t3, 3

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR # bottom left = middle left 
	add $s5, $s5, $s4

	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right = center
	add $s5, $s5, $s4
	add $s5, $s5, $s4			# bottom center = center

	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = center
	add $s5, $s5, $s4

	#######################
	
	add $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = top center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	###### END ############

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, firstRowRightEdgePixel

	## Increment row
	add  $t3, $t3, $t9  	# advance current position by the number of padding bytes
	
nextRow:
	#Calculate start of inner row position
	add $t6, $t3, 3

  	#Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

leftEdgePixel:
	##### START ##########

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left = center
	move $s5, $s4
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4
	
	#######################
	
	sub $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	#######################
	
	add $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left = top center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	###### END ############

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
	##### START ##########
	sub $t3, $t3, 3

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4
	
	#######################
	
	sub $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	#######################
	
	add $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	###### END ############

	
	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, middlePixels


rightEdgePixel:
	##### START ##########
	sub $t3, $t3, 3

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right = center
	add $s5, $s5, $s4
	
	#######################
	
	sub $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = bottom center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	#######################
	
	add $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = top center
	add $s5, $s5, $s4
	
	sub $t3, $t3, $t8

	add $t3, $t3, 3

	###### END ############

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
	add  $t3, $t3, $t9  		# advance current position by the number of padding bytes
	blt  $t3, $t5, nextRow		# if current position is less than 'end of middle rows' position process the next row


	# If total number of bytes read equals bitmap_size it is the last block
	lw  $t5, size
	beq $t2, $t5, lastRowInit


lastRowInit:
	# Calculate start of inner row position
	add $t6, $t3, 3

  	# Calculate end of inner row position:
  	add $t4, $t3, $t8	# Start of row + row size 
  	sub $t4, $t4, $t9 	# - padding 
  	sub $t4, $t4, 3		# - 1 pixel

lastRowLeftEdgePixel:
	##### START ##########

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left = center
	move $s5, $s4
	add $s5, $s5, $s4			# top center = center

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top left = center
	add $s5, $s5, $s4

	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4

	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = middle right
	add $s5, $s5, $s4
	
	#######################
	
	sub $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left = bottom center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	###### END ############

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
	##### START ##########
	sub $t3, $t3, 3

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# top left = middle left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4

	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# top center = center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right
	add $s5, $s5, $s4

	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = middle right
	add $s5, $s5, $s4

	#######################
	
	sub $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR # bottom left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 6
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	add $t3, $t3, 3

	###### END ############

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Increment byte
	add $t3, $t3, 1
	blt $t3, $t4, lastRowMiddlePixels

lastRowRightEdgePixel:
	##### START ##########
	sub $t3, $t3, 3

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR 	# middle left 
	move $s5, $s4

	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR # top left = middle left 
	add $s5, $s5, $s4

	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CENTER_FACTOR	# center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# middle right = center
	add $s5, $s5, $s4
	add $s5, $s5, $s4			# top center = center

	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# top right = center
	add $s5, $s5, $s4

	#######################
	
	sub $t3, $t3, $t8
	
	add $s4, $t7, $t3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR 	# bottom left
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, EDGE_FACTOR	# bottom center
	add $s5, $s5, $s4
	
	add $s4, $t7, $t3
	add $s4, $s4, 3
	lbu $s4, ($s4)
	mul $s4, $s4, CORNER_FACTOR	# bottom right = bottom center
	add $s5, $s5, $s4
	
	add $t3, $t3, $t8

	add $t3, $t3, 3

	###### END ############

	# Calculate new pixel's byte value:
	div $s5, $s3		
	mflo $s4		
	
	# Store this value in outbuffer:
	sb $s4, outbuffer($t3)
	
	# Go to the next right edge pixel's byte
	add $t3, $t3, 1
	blt $t3, $t6, lastRowRightEdgePixel

	## Increment row
	add  $t3, $t3, $t9  	# advance current position by the number of padding bytes


	# Here we decide whether to change the buffer and continue processing the middle rows of the image 
	# or to jump to processing the final row 
	
	# Suppose we are pocessing the first block
	# In our outbuffer we have first row and rows up until n-1 (n being the number of rows that fit into that buffer)
	# We need to write to file from the start of the outbuffer
	
	# Suppose we are processing second or higher block of bitmap in our outbuffer we have rows from 2 to n-1
	# We need to write to file from the 2nd row of the outbuffer 
	
	# Suppose we are processing the final block
	# In outbuffer we have rows from the 2nd to the n'th
	# We need to write to file from the 2nd oud row of the outbuffer


writeToFile:
	# Write bitmap to output file:
	move $a0, $t1        	 	# output file descriptor 
	la   $a1, outbuffer	 	# address of buffer from which to write
	move $a2, $t2		 	 	# buffer length
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
