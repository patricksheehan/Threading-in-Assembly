# David Hwang, Spencer Stecko, and Patrick Sheehan
# This file contains assembly code for the C function "ucdsort" which uses
# threads to sort an array of given length

.data   # step one: set up space for all of the globals that we will use

    # Must first set up our global variables
    # pthread_id == &id[0] for pthread_create and pthread_join
    # pthread_barrier will be of size sufficient for pthread_barrier_init
    # chunksize will be used whenever we portion out "work" to each thread
    # nThreads will hold the passed argument "nth" for global use
    # sizeofArray will hold the passed argument "n", the size of array x
    # x will be our global version of the passed array "x" (int *)
    # minMax will be an array where minMax[threadNumber] = min for that thread
    # and minMax[threadNumber+1] = max for that thread
    # numberToWrite will be an array where numberToWrite[threadNumber] will have
    # the number of elements that thread will be writing to the original array x
.globl pthread_id, pthread_barrier, chunksize, nThreads, sizeofArray, x, minMax
.globl numberToWrite, pthread_barrier2, pthread_barrier3

pthread_id:
    .space 4      # pthread_id is a pointer, needs 4 bytes, we will later use 
                  # malloc to allocate space for pthread_t [nth]
pthread_barrier:
    .space 20     # pthread_barrier_t requires 20 bytes of memory
pthread_barrier2:
    .space 20
pthread_barrier3:
    .space 20
chunksize:
    .space 4      # chucksize requires 4 bytes of memory (int)
nThreads:
    .space 4      # nThreads requires 4 bytes of memory (int)
sizeofArray:
    .space 4      # sizeofArray requires 4 bytes of memory (int)
x:
    .space 4      # x is array, the space required is 4 bytes, sizeof(pointer)
minMax:
    .space 4      # minMax is array, the space required 4 bytes, sizeof(pointer)
                  # minMax will be given space for nThreads*2 elements
numberToWrite:
    .space 4      # numberToWrite will be how threads publicize how many element
                  # s they are to write to the original array x
                  # numberToWrite will require space for nThreads elements
cullingArray:
    .space 4      # cullingArray will be of size cullingArray[n*nth]

.text

.equ WORD, 4
.equ sizeof_pthread_t, 4

.globl ucdsort    # Make ucdsort visible (callable from c)

ucdsort:    # when ucdsort() is called, the stack should appear as follows:
            # top->bottom: Return address, x, n, nth
initialize: # Step 1: set global variables and allocate needed memory
    push %ebx                # must save EBX from our function, will pop at end

    movl (2*WORD)(%esp), %eax
    movl %eax, x             # store int * x in x (essentially make x global)
    movl (3*WORD)(%esp), %eax# EAX holds size of array x
    movl %eax, sizeofArray   # store n in sizeofArray
    movl (4*WORD)(%esp), %ebx# use EBX for this because we will use it
                             # directly from the register when we can
    movl %ebx, nThreads      # store the number of threads to be used
    
    # now set up cullilngarray[nThreads*n]
    imull %ebx               # EAX now stores nthreads*n
    movl $WORD, %ecx         
    imull %ecx               # make that word size              
    push %eax                # argument for malloc
    call malloc              # allocate space
    movl %eax, cullingArray  # put return value in cullingArray
    addl $WORD, %esp         # clean stack

    movl (3*WORD)(%esp), %eax# move n back to EAX for next setup
    
    # now set up chunksize = sizeofArray/nthreads
    movl $0, %edx            # for IDIVL
    idivl %ebx               # divide input thread size (n) by nThreads
    movl %eax, chunksize     

    movl $(WORD), %eax       # put wordSize in EAX
    imull %ebx               # multiply by nThreads
    push %eax                # prepare argument fo numberToWrite size = nThreads
    call malloc              
    movl %eax, numberToWrite # numberToWrite now has an appropriate sized array
    addl $WORD, %esp         # clean stack

    # minMax is of size: sizeof(int)*nThreads*2
    movl $(2*WORD), %eax     # prepare operand for IMUL
    imull %ebx               # multiply nThreads * 2, store in EAX              
    push %eax                # prepare argument for minMax array
    call malloc
    movl %eax,  minMax       # minMax now has an appropriate sized array!
    addl $WORD, %esp         # clean up the stack
    
    # pthread_id is of size nThreads*(sizeof(pthread_t)
    movl $sizeof_pthread_t, %eax     # prepare operand for IMUL
    imull %ebx               # need space for nThreads*sizeof(pthread_id)
    push %eax                # argument for malloc for id array
    call malloc
    movl %eax, pthread_id    # pthread_id == &id[0]
    addl $WORD, %esp         # clean up the stack

    # now to initialize pthread_barrier
    # pthread_barrier takes input &barrier, NULL, nThreads
    push %ebx                # nThreads
    push $0                  # NULL
    push $pthread_barrier    # &barrier
    call pthread_barrier_init
    addl $(3*WORD), %esp     # clean up the stack
    
    push %ebx                # nThreads
    push $0                  # NULL
    push $pthread_barrier2   # &barrier
    call pthread_barrier_init
    addl $(3*WORD), %esp     # clean up the stack

    push %ebx                # nThreads
    push $0                  # NULL
    push $pthread_barrier3    # &barrier
    call pthread_barrier_init
    addl $(3*WORD), %esp     # clean up the stack

    movl $0, %eax            # prepare EAX to be the counter for our loop!
    movl pthread_id, %ecx    # ECX now holds &id[0]
   
pthreadCreateLoop:  # Step 2: start the threads
    cmpl %eax, %ebx          # if EAX == EBX, all threads have been started
    jz pthreadJoin           # jump to our join section,
    
    # otherwise, prepare arguments for pthread_create
    # pthread_create takes input: &id[i], NULL, pthreadFunction, i
    push %eax                # push i
    push $pthreadFunction    # push address to pthreadFunction
    push $0                  # push NULL
    push %ecx                # push &id[i] son
    call pthread_create      # Call pthread_create
    pop %ecx                 # save ECX
    addl $(WORD*2), %esp     # clean middle arguments
    pop %eax                 # preserve counter
    incl %eax                # increment counter (i++)
    addl $(sizeof_pthread_t), %ecx  # make ECX point to &id[i++]

    jmp pthreadCreateLoop    # Loop 
    
pthreadFunction:
    # Step 3: set up for each thread's minMax loop
    # first set that thread's min and max to the first element: x[0]
    # minMax[2*threadNumber] =  x[0]
    push %ebx                # we will be using EBX later!
    movl (2*WORD)(%esp), %ecx# we use ECX to store the current thread's number
    movl x, %edx             # EDX now holds &x[0]
    movl (%edx), %eax        # EAX now holds x[0]
    movl minMax, %edx        # EDX now holds &minMax[0]
    movl %eax, (%edx,%ecx,2*WORD)     # Move x[0] into minMax[2*threadNumber]
    movl %eax, WORD(%edx,%ecx,2*WORD) # Move x[0] into minMax[2*threadNumber+1]

    # At this point, we have initialized the minMax recording array! (wooo!)
    # Now we have to start the minMax loop
    # here are the conditions:
    # from i = threadNumber*chunksize
    # to i < j where j = sizeofArray (if last thread) or (threadNum+1)*chunksize
    movl chunksize, %eax     # EAX now holds chunksize
    imull %ecx               # EAX now holds chunksize*threadNumber
    push %eax                # store on stack
    
    incl %ecx                # last thread will have threadNumber nThreads-1
    cmpl nThreads, %ecx      # if last thread
    jz specialj              # Otherwise, j = (threadNumber+1)*chunksize
    movl chunksize, %eax     # EAX now holds chunksize
    imull %ecx               # EAX now holds (threadNumber+1)*chunksize == j
    decl %ecx                # ECX holds threadNumber again
    push %eax                # put j on stack

    jmp findMinMaxLoop1

specialj:
    movl sizeofArray, %eax   # EAX now holds j, our end counter condition
    decl %ecx                # restore threadNumber to original value
    push %eax                # put j on stack

findMinMaxLoop1:
    # at this point, (%esp) holds i and 4(%esp) holds j
    movl 4(%esp), %edx      # put i in EDX
    cmpl (%esp), %edx       # if at end of loop
    jz overallMinMax        # find overall min and max
    
    incl 4(%esp)            # increment i
    
    movl x, %ebx            # EBX now holds &x[0]
    movl (%ebx,%edx,WORD), %ebx       # put &x[0]+(i*WORD) in %ebx == x[i]
    movl minMax, %edx       # put &minMax[0] in %edx
    
    cmpl %ebx, (%edx,%ecx,2*WORD)     # examine minMax(threadnum*2) - x[i]
    jg newMinimum
    cmpl %ebx, WORD(%edx,%ecx,2*WORD) # &x[i] to minmax[2*threadNumber+1]
    jl newMaximum
   
    # Otherwise
    jmp findMinMaxLoop1

newMinimum:
    movl %ebx, (%edx,%ecx,2*WORD)     # update minMax[2*threadNumber]
    jmp findMinMaxLoop1               # iterate
     
newMaximum:
    movl %ebx, WORD(%edx,%ecx,2*WORD) # update minMax[2threadNumber+1]
    jmp findMinMaxLoop1               # iterate

overallMinMax:
    addl $(2*WORD), %esp    # remove our loop's arguments

    # test for new overall min
    movl minMax, %edx       # put &minMax[0] in %edx
    movl (%edx,%ecx,2*WORD), %ebx     # put minMax[threadNum*2] in EBX
    cmpl %ebx, (%edx)       # examine minMax[0] - minMax[threadnum*2]
    jle testOverallMax

newOverallMin:
    movl %ebx, (%edx)       # update overall min (minMax[0])
 
testOverallMax:
    addl $WORD, %edx        # put &minMax[1] in %edx
    movl (%edx,%ecx,2*WORD), %ebx      # put minMax[threadNum*2+1] in EBX
    cmpl %ebx, (%edx)       # minMax[1] - minMax[threadnum*2+1]
    jge barrier1

newOverallMax:
    movl %ebx, (%edx)       # update overall max (minMax[1])

barrier1:
    push $pthread_barrier               # &barrier_variable argument
    call pthread_barrier_wait           # must wait for all threads to update
    addl $WORD, %esp        # clean stack

cullArray:
    # now to set up new chunksize to cull elements from the array
    # chunksize = (max-min+1)/nthreads
    movl $0, %edx            # for idiv
    movl minMax, %ebx        # ECX now holds &minMax[0]
    movl WORD(%ebx), %eax    # EAX now holds minMax[0]
    subl (%ebx), %eax        # EAX now holds minMax[0] + minMax[1]
    incl %eax                # EAX now holds minMax[0] + minMax[1] + 1
    movl nThreads, %ecx      # ECX now holds nThreads
    idivl %ecx               # EAX should now hold (min+max+1)/nThreads
    movl %eax, chunksize     # chunksize set

    push $0                  # this will be our counter for # of elements cull'd
    push $0                  # this will be our counter for the first loop

    movl (4*WORD)(%esp), %ecx# put threadNumber into ECX
    imull %ecx               # multiply current threadNumber*chunksize
    addl (%ebx), %eax        # add minMax[0] to i
    push %eax                # push "i" onto the stack

    movl sizeofArray, %eax   # put size of x into EAX
    imull %ecx               # multiply by threadNumber to get offset   
    movl $WORD, %edx         # multiply offset by wordsize to get address offset
    imull %edx               # ^
    movl cullingArray , %ecx # EAX now holds &cullingArray[0]
    addl %eax, %ecx          # add address offset
    push %ecx                # put on stack
    push %ecx                # store a copy

    movl nThreads, %edx      # move nThreads to EBX for comparison
    decl %edx
    cmpl (7*WORD)(%esp), %edx# if last thread, special j needs to be set
    jz specialj2
    # Otherwise, j = (threadNumber+1)*chunksize + minMax[0]
    movl (2*WORD)(%esp), %eax# put i == chunksize(threadNumber) + minimum
    addl chunksize, %eax     # j == chunksize(threadnumber+1) + minimum
    push %eax                # push "j" onto the stack

    jmp cullArrayLoop

specialj2:
    incl WORD(%ebx)
    push WORD(%ebx)          # push "j" == max onto stack

cullArrayLoop:
    movl (4*WORD)(%esp), %eax	# EAX holds our counter
    cmpl %eax, sizeofArray   	# if we've gone through all elements
    jz publishNumberToWrite  	# done
    #ELSE set up loop through our threadNumber's chunk
  
    incl (4*WORD)(%esp)     	# increment counter
    movl (3*WORD)(%esp), %ebx 	# EBX will hold our i for the nested loop
    movl x, %ecx             	# move &x[0] into ECX
    movl (%ecx,%eax,WORD), %edx # put x[i] into EDX

loopThroughChunk:               
    cmpl %ebx, (%esp)        # j is on top of the stack
    jz cullArrayLoop         # if done searching for elements in our range

    cmpl %ebx, %edx          # if x[i] == %ebx in our range
    jz cullElement
    incl %ebx                # increment counter
    jmp loopThroughChunk
    
cullElement:
    movl (2*WORD)(%esp), %ecx   # address to put the element to cull in ECX
    movl %ebx, (%ecx)      	# put element in sed address
    incl (5*WORD)(%esp)     	# increment # of elements to be written
    addl $WORD, (2*WORD)(%esp)	# point to next free space for this threadNumber
    incl %ebx               	# increment counter still
    jmp loopThroughChunk    	# Loop

publishNumberToWrite:
    movl WORD(%esp), %ecx   # save our address offset for threadNumber in ECX
    addl $(5*WORD), %esp    # clean stack
    pop %eax                # pop number to write into EAX
    movl (2*WORD)(%esp), %edx       # put threadNum in EDX
    movl numberToWrite, %ebx        # put &numberToWrite[0] into EBX
    movl %eax, (%ebx,%edx,WORD)     # write numtowrite

barrier2:   # must wait for all threads to publish
    push %ecx
    push %edx
    push $pthread_barrier2               # &barrier_variable argument
    call pthread_barrier_wait           # must wait for all threads to update
    addl $WORD, %esp                    # clean stack
    pop %edx
    pop %ecx

setupWrite:   # write unsorted culled elements to x
            # ECX holds the address offset for this threadNumber in culled array
            # EBX holds &numberToWrite[0]
            # EDX holds threadNumber
    # now to figure out where to start in x array\
    movl $0, %eax
findOffsetLoop:
    cmpl $0, %edx       # use threadNumber as our counterŒ
    jz writeToX
    decl %edx
    addl (%ebx,%edx,WORD), %eax
    jmp findOffsetLoop

writeToX:
    push %eax                   # push offset
    movl (3*WORD)(%esp), %edx   # threadNumber to EDX
    push (%ebx,%edx,WORD)       # put counter numberToWrite[threadNumber]
    push (%ebx,%edx,WORD)       # put counter numberToWrite[threadNumber] copy
                                # on stack
    movl x, %ebx
writeToXLoop:
    cmpl $0, (%esp)             # written all elements?
    jz qsortFunction            # done
    decl (%esp)

    movl (%ecx), %edx           # put cullingArray[offset+i] in EDX
    movl %edx, (%ebx,%eax,WORD) # put EDX into where we want in x
    addl $WORD, %ecx            # point ECX at next element in culled
    incl %eax                   # point increment offset to next element in X
    jmp writeToXLoop

qsortFunction:
#########BARRIER 3#########
    push %ecx
    push %edx
    push $pthread_barrier3               # &barrier_variable argument
    call pthread_barrier_wait           # must wait for all threads to update
    addl $WORD, %esp                    # clean stack
    pop %edx
    pop %ecx

########Function##########
    addl $WORD, %esp            # clean stack from writeToX
    pop %edx                    # EDX now holds numberToWrite[threadNumber]
    pop %eax                    # EAX holds offset
    
    #movl $WORD, %ecx
    #imull %ecx
    #movl x, %ecx
    #addl %eax, %ecx

    movl x, %ebx                # ebx is the start of x
    push $offset                	# move offset bytes over
    push $WORD                  # size of int
    push %edx                   # length of portion
    #push (%ebx,%eax,WORD)      # put offset of x as start of portion

    #push x                     #for testing purposes

    movl $WORD, %ecx
    imull %ecx
    movl x, %ecx
    addl %eax, %ecx
    push %ecx
    movl $0, %eax  #trash line for debugging 

    call qsort
    addl $(4*WORD), %esp
    pop %ebx                # restore EBX
    ret

pthreadJoin:
    movl $0, %eax            # prepare EAX to be the counter for our loop!
    movl pthread_id, %ecx    # ECX now holds &id[0]

pthreadJoinLoop:
    cmpl %eax, %ebx          # if EAX == EBX, all threads have been terminated
    jz done                  # We DONE. Peace.
    
    # otherwise, prepare arguments for pthread_create
    # pthread_join takes input: id[i], NULL, pthreadFunction, i
    push %eax                # save EAX
    push %ecx                # save ECX (Is there a better way?)
    push $0                  # push NULL
    push (%ecx)              # push id[i]
    call pthread_join        # Call pthread_join (trashes EAX, ECX, EDX)
    addl $(2*WORD), %esp     # clean arguments
    pop %ecx                 # save ECX
    pop %eax                 # preserve counter

    incl %eax                # increment counter (i++)
    addl $(sizeof_pthread_t), %ecx     # make ECX point to &id[i++]

    jmp pthreadJoinLoop      # Loop

offset:
    movl (2*WORD)(%esp),  %edx# EAX stores arg1
    movl WORD(%esp),  %ecx    # EBX stores arg2
    movl (%ecx), %eax
    subl (%edx), %eax         # EAX stores EAX-EBX
    ret                       # done


done:   # finished joining loops, return from UCDSORT
    pop %ebx                 # this is to restore the value of EBX
    ret                      # this should return from ucdsort
