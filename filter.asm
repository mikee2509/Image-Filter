.data
		
header:		.space 56
size:		.space 4  # space for input image bitmap size in bytes
width:		.space 4  # space for image width in pixels
height:		.space 4  # space for image height in pixels

welcomeMsg:	.asciiz "High Pass / Low Pass filter\n   Michal Sieczkowski 04.2017\n\n"
openedMsg:	.asciiz "File opened\n   Processing...\n"
errorMsg:	.asciiz "Error opening file\n"
inFileName:	.asciiz "aaa.bmp"
outFileName:	.asciiz "bbb.bmp"


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
  	move $a0, $t0     
	la   $a1, header+2   	  # lw laduje tylko slowa o adreasie podzielnym przez 4
  	li   $a2, 54
  	li   $v0, 14  	 
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

##---------------------------------------

	# Write header to output file:
	move $a0, $t1        # output file descriptor 
	la   $a1, header+2   # address of buffer from which to write
	li   $a2, 54         # header length
	li   $v0, 15         # write to file
	syscall
	
	
	b exit
	
fileError:
	la $a0, errorMsg 	# Error opening file message
	li $v0, 4
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