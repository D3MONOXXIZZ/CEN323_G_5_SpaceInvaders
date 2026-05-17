org 100h                ; Define origin for DOS .COM executable (starts at offset 0100h)

jmp Start               ; Jump over the data declarations to the main program entry point

;; ==========================================
;; GAME DATA & VARIABLES
;; ==========================================
GameState db 0          ; 0 = Playing, 1 = Win, 2 = Game Over
ExitFlag db 0           ; 1 = Player requested to quit (ESC)

PlayerX db 40           ; Player starting X coordinate (middle of 80-column screen)
PlayerY db 23           ; Player Y coordinate (near bottom of 25-row screen)

LastTick dw 0           ; Used for frame rate synchronization (BIOS timer ticks)

EnemyDir db 1           ; Enemy movement direction: 1 = Right, 0FFh (-1) = Left
EnemyMoveDelay dw 4     ; How many frames to wait before moving enemies (controls speed)
EnemyMoveCounter dw 0   ; Counter to track when to move enemies
EnemyAnim db 0          ; Enemy animation frame (0 or 1)

Score dw 0              ; Current player score
PrevScore dw 0          ; Used to check if the score needs to be redrawn

;; --- Bullet Variables ---
BulletCount equ 5       ; Max number of bullets on screen at once
BulletActive db BulletCount dup (0) ; Array: 1 if bullet is active, 0 if free
BulletX db BulletCount dup (0)      ; Array: Bullet X positions
BulletY db BulletCount dup (0)      ; Array: Bullet Y positions
PrevBulletActive db BulletCount dup (0) ; For erasing old frames (anti-flicker)
PrevBulletX db BulletCount dup (0)
PrevBulletY db BulletCount dup (0)

;; --- Enemy Variables ---
EnemyRows equ 5         ; 5 rows of enemies
EnemyCols equ 11        ; 11 columns of enemies
EnemyCount equ EnemyRows*EnemyCols ; Total 55 enemies
EnemyAlive db EnemyCount dup (0)   ; Array: 1 if alive, 0 if destroyed
EnemyX db EnemyCount dup (0)       ; Array: Enemy X positions
EnemyY db EnemyCount dup (0)       ; Array: Enemy Y positions
PrevEnemyAlive db EnemyCount dup (0) ; For erasing old frames (anti-flicker)
PrevEnemyX db EnemyCount dup (0)
PrevEnemyY db EnemyCount dup (0)

PrevPlayerX db 40       ; For erasing old player position

;; --- Graphics & Strings ---
EnemySpriteW equ 3      ; Enemy width is 3 characters
EnemySprite0 db '/', 'X', '\' ; Animation frame 1
EnemySprite1 db '\', 'X', '/' ; Animation frame 2

HudScore db 'SCORE:',0
HudQuit db 'ESC:QUIT  R:RESTART',0

MsgWin db 'YOU WIN!',0
MsgGameOver db 'GAME OVER',0
MsgPrompt db 'R=RESTART  ESC=QUIT',0

;; ==========================================
;; MAIN PROGRAM ENTRY
;; ==========================================
Start:
    ; Set up Data Segment (DS) and Extra Segment (ES) to match Code Segment (CS)
    push cs
    pop ds
    push cs
    pop es
    
    ; Set up the stack safely
    cli                 ; Clear interrupts while modifying stack
    push cs
    pop ss
    mov sp, 0FFFEh      ; Set stack pointer to top of segment
    sti                 ; Restore interrupts

    call SetTextMode    ; Initialize standard 80x25 text mode
    call ResetGame      ; Set up initial game state

;; ==========================================
;; CORE GAME LOOP
;; ==========================================
MainLoop:
    cmp ExitFlag, 0     ; Check if ESC was pressed
    jne Quit            ; If yes, exit to DOS

    cmp GameState, 0    ; Check if we are actively playing
    jne NotPlaying      ; If not (Win/Loss), jump to handle those screens

    ; -- Active Gameplay Loop --
    call FrameSync           ; Lock frame rate using BIOS timer
    call PollInput           ; Read keyboard input
    call ErasePrevEntities   ; Erase old sprites to prevent trails/flicker
    call UpdateBullets       ; Move bullets up
    call UpdateEnemies       ; Move enemies left/right/down
    call CheckCollisions     ; Check if bullets hit enemies
    call CheckWinLose        ; Check if player won or enemies reached the bottom
    
    cmp GameState, 0         ; Did state change after checks?
    jne MainLoop             ; If yes, restart loop to trigger win/lose screens
    
    call DrawScoreIfChanged  ; Update HUD
    call DrawEnemies         ; Render enemies at new positions
    call DrawBullets         ; Render bullets at new positions
    call DrawPlayer          ; Render player
    call SyncPrevState       ; Save current positions for next frame's erasure
    jmp MainLoop             ; Repeat

NotPlaying:
    cmp GameState, 1    ; Is state 1 (Win)?
    jne ShowLose        ; If not, it must be 2 (Game Over)
    call ShowWinScreen  ; Display Win Screen
    jmp MainLoop

ShowLose:
    call ShowGameOverScreen ; Display Game Over Screen
    jmp MainLoop

Quit:
    call SetTextMode    ; Reset video mode to clear screen
    mov ax, 4C00h       ; DOS interrupt to terminate program
    int 21h

;; ==========================================
;; SETUP & SYSTEM FUNCTIONS
;; ==========================================
SetTextMode proc near
    mov ax, 0003h       ; BIOS func 00h: Set video mode, mode 03h: 80x25 16-color text
    int 10h
    ret
SetTextMode endp

ResetGame proc near
    ; Reset all core variables to starting defaults
    mov ExitFlag, 0
    mov GameState, 0
    mov PlayerX, 40
    mov PlayerY, 23
    mov EnemyDir, 1
    mov EnemyMoveDelay, 4
    mov EnemyMoveCounter, 0
    mov EnemyAnim, 0
    mov Score, 0
    mov PrevScore, 0

    call ClearScreen
    call ClearBullets
    call InitEnemies    ; Generate the grid of enemies
    call DrawHUD        ; Draw static text (SCORE:, ESC:QUIT)
    call DrawEnemies
    call DrawPlayer
    call SyncPrevState  ; Sync logic so first frame doesn't erase incorrectly
    call InitLastTick   ; Reset the timer for frame syncing
    ret
ResetGame endp

InitLastTick proc near
    push ax
    push cx
    push dx
    mov ah, 00h         ; BIOS int 1Ah, func 00h: Get System Time
    int 1Ah
    mov LastTick, dx    ; Store lower word of tick count
    pop dx
    pop cx
    pop ax
    ret
InitLastTick endp

FrameSync proc near
    push ax
    push cx
    push dx
    mov cx, 5000        ; Failsafe timeout counter
FrameSync_Wait:
    mov ah, 00h         ; Get System Time
    int 1Ah
    cmp dx, LastTick    ; Compare current tick with last tick
    jne FrameSync_Got   ; If different, a tick has passed (18.2 ticks/sec)
    loop FrameSync_Wait ; Otherwise, keep waiting
FrameSync_Got:
    mov LastTick, dx    ; Update LastTick for the next frame
    pop dx
    pop cx
    pop ax
    ret
FrameSync endp

;; ==========================================
;; INPUT HANDLING
;; ==========================================
PollInput proc near
    push ax
    push bx
    push dx

PollInput_Check:
    mov ah, 01h         ; BIOS int 16h, func 01h: Check keystroke status
    int 16h
    jz PollInput_Done   ; Zero flag set if no key pressed
    mov ah, 00h         ; BIOS int 16h, func 00h: Read keystroke (removes from buffer)
    int 16h

    cmp al, 1Bh         ; Check for ASCII 27 (ESC key)
    jne PollInput_NotEsc
    mov ExitFlag, 1     ; Trigger exit
    jmp PollInput_Done

PollInput_NotEsc:
    cmp al, 'r'         ; Check lowercase 'r'
    je PollInput_Restart
    cmp al, 'R'         ; Check uppercase 'R'
    je PollInput_Restart

    cmp al, ' '         ; Check Spacebar
    je PollInput_Fire

    cmp al, 'a'         ; Check A
    je PollInput_Left
    cmp al, 'A'
    je PollInput_Left
    cmp al, 'd'         ; Check D
    je PollInput_Right
    cmp al, 'D'
    je PollInput_Right

    cmp al, 0           ; Extended keycode (like arrows)? AL will be 0
    jne PollInput_Check
    cmp ah, 4Bh         ; Left Arrow scan code
    je PollInput_Left
    cmp ah, 4Dh         ; Right Arrow scan code
    je PollInput_Right
    jmp PollInput_Check ; Loop back to drain buffer if unknown key

PollInput_Left:
    mov al, PlayerX
    cmp al, 0           ; Don't let player go past left edge
    je PollInput_Done   ; Exit if at edge
    dec al              ; Move left
    mov PlayerX, al
    jmp PollInput_Done  ; Exit after moving

PollInput_Right:
    mov al, PlayerX
    cmp al, 79          ; Don't let player go past right edge
    jae PollInput_Done  ; Exit if at edge  
    inc al              ; Move right
    mov PlayerX, al
    jmp PollInput_Done  ; Exit after moving

PollInput_Fire:
    call FireBullet     ; Spawn a bullet
    jmp PollInput_Done  ; Exit after firing

PollInput_Restart:
    cmp GameState, 0    ; Only allow restart if not actively playing? Wait, logic says:
    je PollInput_Check  ; Ignore restart if already playing (GameState 0)
    call ResetGame
    jmp PollInput_Done

PollInput_Done:
    pop dx
    pop bx
    pop ax
    ret
PollInput endp

;; ==========================================
;; BULLET LOGIC
;; ==========================================
ClearBullets proc near
    push ax
    push cx
    push di
    mov cx, BulletCount ; Loop through all bullets
    mov di, 0
ClearBullets_Loop:
    mov byte ptr [BulletActive+di], 0 ; Deactivate bullet
    mov byte ptr [BulletX+di], 0
    mov byte ptr [BulletY+di], 0
    inc di
    loop ClearBullets_Loop
    pop di
    pop cx
    pop ax
    ret
ClearBullets endp

FireBullet proc near
    push ax
    push bx
    push cx
    push di

    mov di, 0
    mov cx, BulletCount
FireBullet_Find:
    cmp byte ptr [BulletActive+di], 0 ; Find the first inactive bullet slot
    je FireBullet_Use
    inc di
    loop FireBullet_Find
    jmp FireBullet_Done               ; If no slots, can't fire

FireBullet_Use:
    mov al, PlayerY
    cmp al, 2           ; Don't fire if too close to the top HUD
    jbe FireBullet_Done
    dec al              ; Start bullet 1 row above player
    mov byte ptr [BulletY+di], al
    mov al, PlayerX     ; Match bullet X to player X
    mov byte ptr [BulletX+di], al
    mov byte ptr [BulletActive+di], 1 ; Mark bullet as active

FireBullet_Done:
    pop di
    pop cx
    pop bx
    pop ax
    ret
FireBullet endp

UpdateBullets proc near
    push ax
    push cx
    push di
    mov cx, BulletCount
    mov di, 0
UpdateBullets_Loop:
    cmp byte ptr [BulletActive+di], 0 ; Skip inactive bullets
    je UpdateBullets_Next
    mov al, byte ptr [BulletY+di]
    cmp al, 2                         ; Did it hit the top of the screen?
    jbe UpdateBullets_Kill
    dec al                            ; Move bullet UP by 1 Y coordinate
    mov byte ptr [BulletY+di], al
    jmp UpdateBullets_Next
UpdateBullets_Kill:
    mov byte ptr [BulletActive+di], 0 ; Deactivate bullet when off-screen
UpdateBullets_Next:
    inc di
    loop UpdateBullets_Loop
    pop di
    pop cx
    pop ax
    ret
UpdateBullets endp

;; ==========================================
;; ENEMY LOGIC
;; ==========================================
InitEnemies proc near
    push ax
    push bx
    push cx
    push dx
    push di

    mov di, 0           ; Index in enemy array
    xor bh, bh          ; bh = Row counter
InitEnemies_Row:
    xor bl, bl          ; bl = Col counter
InitEnemies_Col:
    mov byte ptr [EnemyAlive+di], 1 ; Mark enemy as alive  
    
; Calculate Enemy X: (Col * 6) + 10
    mov al, bl
    mov ah, 0
    mov cl, 6
    mul cl
    add ax, 10
    mov byte ptr [EnemyX+di], al

    ; Calculate Enemy Y: (Row * 2) + 3
    mov al, bh
    mov ah, 0
    mov cl, 2
    mul cl
    add ax, 3
    mov byte ptr [EnemyY+di], al

    inc di
    inc bl
    cmp bl, EnemyCols
    jb InitEnemies_Col  ; Loop columns
    inc bh
    cmp bh, EnemyRows
    jb InitEnemies_Row  ; Loop rows

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret
InitEnemies endp 
UpdateEnemies proc near
    push ax
    push bx
    push cx
    push dx
    push si

    ; Frame delay logic to make enemies move slower than bullets
    mov ax, EnemyMoveCounter
    inc ax
    mov EnemyMoveCounter, ax
    cmp ax, EnemyMoveDelay
    jb UpdateEnemies_Done       ; If counter < delay, skip moving this frame
    mov EnemyMoveCounter, 0     ; Reset counter

    call GetEnemyBounds         ; Find the leftmost (dh) and rightmost (dl) active enemy edges

    mov al, EnemyDir
    cmp al, 1
    jne UpdateEnemies_CheckLeft ; If not moving right, check left
    
    ; --- Moving Right ---
    cmp dl, 79                  ; Has rightmost edge hit screen bound (79)?
    jb UpdateEnemies_MoveHoriz  ; If not, continue horizontal move
    mov EnemyDir, 0FFh          ; If hit, change direction to Left (-1)
    call DropEnemies            ; Move all enemies down one row
    call ToggleEnemyAnim        ; Swap sprite frame
    jmp UpdateEnemies_Done

UpdateEnemies_CheckLeft:
    ; --- Moving Left ---
    cmp al, 0FFh
    jne UpdateEnemies_MoveHoriz
    cmp dh, 0                   ; Has leftmost edge hit screen bound (0)?
    ja UpdateEnemies_MoveHoriz  ; If not, continue horizontal move
    mov EnemyDir, 1             ; If hit, change direction to Right (1)
    call DropEnemies
    call ToggleEnemyAnim
    jmp UpdateEnemies_Done

UpdateEnemies_MoveHoriz:
    call MoveEnemiesHoriz       ; Apply X movement to all enemies
    call ToggleEnemyAnim        ; Swap sprite frame for walking effect 
    
UpdateEnemies_Done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
UpdateEnemies endp

GetEnemyBounds proc near
    ; Finds the exact bounding box of the active enemy swarm
    ; Returns: dh = Leftmost X coordinate, dl = Rightmost X coordinate
    push ax
    push bx
    push cx
    push si

    mov dh, 79          ; Start Left bounds high
    mov dl, 0           ; Start Right bounds low
    mov cx, EnemyCount
    mov si, 0
GetEnemyBounds_Loop:
    cmp byte ptr [EnemyAlive+si], 0 ; Ignore dead enemies
    je GetEnemyBounds_Next
    mov al, byte ptr [EnemyX+si]
    
    ; Check leftmost
    cmp al, dh
    jae GetEnemyBounds_CheckMax
    mov dh, al          ; Update leftmost edge     
    
    GetEnemyBounds_CheckMax:
    ; Check rightmost (requires adding sprite width)
    add al, (EnemySpriteW-1) 
    cmp al, dl
    jbe GetEnemyBounds_Next
    mov dl, al          ; Update rightmost edge
    
GetEnemyBounds_Next:
    inc si
    loop GetEnemyBounds_Loop

    pop si
    pop cx
    pop bx
    pop ax
    ret
GetEnemyBounds endp

ToggleEnemyAnim proc near
    push ax
    mov al, EnemyAnim
    xor al, 1           ; XOR with 1 flips between 0 and 1
    mov EnemyAnim, al
    pop ax
    ret
ToggleEnemyAnim endp
DropEnemies proc near
    ; Moves all alive enemies down by 1 Y unit
    push ax
    push cx
    push si
    mov cx, EnemyCount
    mov si, 0
DropEnemies_Loop:
    cmp byte ptr [EnemyAlive+si], 0
    je DropEnemies_Next
    mov al, byte ptr [EnemyY+si]
    inc al
    mov byte ptr [EnemyY+si], al
DropEnemies_Next:
    inc si
    loop DropEnemies_Loop
    pop si
    pop cx
    pop ax
    ret
DropEnemies endp

MoveEnemiesHoriz proc near
    ; Adds EnemyDir (1 or -1) to every alive enemy's X coordinate
    push ax
    push cx
    push si   
    
mov al, EnemyDir
    mov cx, EnemyCount
    mov si, 0
MoveEnemiesHoriz_Loop:
    cmp byte ptr [EnemyAlive+si], 0
    je MoveEnemiesHoriz_Next
    mov ah, byte ptr [EnemyX+si]
    cmp al, 1
    jne MoveEnemiesHoriz_Left
    inc ah                      ; Move Right
    jmp MoveEnemiesHoriz_Store
MoveEnemiesHoriz_Left:
    dec ah                      ; Move Left
MoveEnemiesHoriz_Store:
    mov byte ptr [EnemyX+si], ah
MoveEnemiesHoriz_Next:
    inc si
    loop MoveEnemiesHoriz_Loop

    pop si
    pop cx
    pop ax
    ret
MoveEnemiesHoriz endp            

;; ==========================================
;; COLLISION & GAME STATE LOGIC
;; ==========================================
CheckCollisions proc near
    ; Nested loop: Checks every active bullet against every active enemy
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov di, 0
    mov cx, BulletCount
CheckCollisions_BulletLoop:
    cmp byte ptr [BulletActive+di], 0
    je CheckCollisions_NextBullet

    mov dl, byte ptr [BulletX+di]
    mov dh, byte ptr [BulletY+di]

    mov si, 0
    mov bx, EnemyCount
CheckCollisions_EnemyLoop:
    cmp byte ptr [EnemyAlive+si], 0
    je CheckCollisions_NextEnemy
    
    ; Is Bullet X >= Enemy X ?
    mov al, byte ptr [EnemyX+si]
    cmp dl, al
    jb CheckCollisions_NextEnemy
    
    ; Is Bullet X <= Enemy X + Sprite Width ?
    add al, (EnemySpriteW-1)
    cmp dl, al
    ja CheckCollisions_NextEnemy
    
    ; Is Bullet Y == Enemy Y ?
    mov al, byte ptr [EnemyY+si]
    cmp al, dh
    jne CheckCollisions_NextEnemy
                                           
 ; --- COLLISION DETECTED ---
    ; Visually erase the enemy immediately to prevent ghosting
    push ax
    push bx
    push dx
    mov al, ' '
    mov bl, 07h
    mov dh, byte ptr [EnemyY+si]
    mov dl, byte ptr [EnemyX+si]
    call PutCharAt
    inc dl
    call PutCharAt
    inc dl
    call PutCharAt
    pop dx
    pop bx
    pop ax
   
   ; Update game state
    mov byte ptr [EnemyAlive+si], 0   ; Kill enemy
    mov byte ptr [BulletActive+di], 0 ; Kill bullet
    mov ax, Score
    add ax, 10                        ; Add 10 points
    mov Score, ax
    jmp CheckCollisions_BreakEnemy    ; Bullet is gone, break inner loop   
    
    CheckCollisions_NextEnemy:
    inc si
    dec bx
    jnz CheckCollisions_EnemyLoop
CheckCollisions_BreakEnemy:

CheckCollisions_NextBullet:
    inc di
    loop CheckCollisions_BulletLoop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
CheckCollisions endp

CheckWinLose proc near
    push ax
    push cx
    push si

; 1. Check Lose Condition (Enemies reached player height)
    mov al, PlayerY
    mov cx, EnemyCount
    mov si, 0
CheckWinLose_EnemyLoop:
    cmp byte ptr [EnemyAlive+si], 0
    je CheckWinLose_NextEnemy
    mov ah, byte ptr [EnemyY+si]
    cmp ah, al
    jb CheckWinLose_NextEnemy   ; If enemy Y < player Y, we're safe
    mov GameState, 2            ; Game Over
    jmp CheckWinLose_Done
CheckWinLose_NextEnemy:
    inc si
    loop CheckWinLose_EnemyLoop

    ; 2. Check Win Condition (Are all enemies dead?)
    mov cx, EnemyCount
    mov si, 0
CheckWinLose_AliveLoop:
    cmp byte ptr [EnemyAlive+si], 0
    jne CheckWinLose_Done       ; Found an alive enemy, not winning yet
    inc si
    loop CheckWinLose_AliveLoop
    mov GameState, 1            ; You Win

CheckWinLose_Done:
    pop si
    pop cx
    pop ax
    ret
CheckWinLose endp
;; ==========================================
;; RENDERING FUNCTIONS
;; ==========================================
DrawHUD proc near
    push ax
    push dx
    push si

    ; Print 'SCORE:' at 0,0
    mov dh, 0
    mov dl, 0
    lea si, HudScore
    call PrintZAt

    ; Print Score Number at 0,7
    mov dh, 0
    mov dl, 7
    mov ax, Score
    call PrintNum6At

    ; Print Quit prompt at 0,55
    mov dh, 0
    mov dl, 55
    lea si, HudQuit
    call PrintZAt

    pop si
    pop dx
    pop ax
    ret
DrawHUD endp

DrawScoreIfChanged proc near
    push ax
    push dx
    mov ax, Score
    cmp ax, PrevScore
    je DrawScoreIfChanged_Done
    mov PrevScore, ax       ; Update cache
    mov dh, 0
    mov dl, 7
    call PrintNum6At        ; Redraw number
DrawScoreIfChanged_Done:
    pop dx
    pop ax
    ret
DrawScoreIfChanged endp

ErasePrevEntities proc near
    ; "Double Buffering" alternative: Overwrite previous positions 
    ; with spaces before drawing the new frame. Prevents flickering.
    push ax
    push bx
    push cx
    push dx
    push si

    mov al, ' '         ; Space character
    mov bl, 07h         ; Light grey text attributes                
    
    
    ; Erase Old Bullets
    mov cx, BulletCount
    mov si, 0
ErasePrevEntities_Bullets:
    cmp byte ptr [PrevBulletActive+si], 0
    je ErasePrevEntities_BulletNext
    mov dh, byte ptr [PrevBulletY+si]
    mov dl, byte ptr [PrevBulletX+si]
    call PutCharAt
ErasePrevEntities_BulletNext:
    inc si
    loop ErasePrevEntities_Bullets

    ; Erase Old Enemies
    mov cx, EnemyCount
    mov si, 0
ErasePrevEntities_Enemies:
    cmp byte ptr [PrevEnemyAlive+si], 0
    je ErasePrevEntities_EnemyNext
    mov dh, byte ptr [PrevEnemyY+si]
    mov dl, byte ptr [PrevEnemyX+si]
    call PutCharAt      ; Char 1
    inc dl
    call PutCharAt      ; Char 2
    inc dl
    call PutCharAt      ; Char 3
ErasePrevEntities_EnemyNext:
    inc si
    loop ErasePrevEntities_Enemies

    ; Erase Old Player
    mov dh, PlayerY
    mov dl, PrevPlayerX
    call PutCharAt

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
ErasePrevEntities endp

SyncPrevState proc near
    ; Copies current coordinates to the Prev coordinates array
    ; Called at the end of the frame
    push ax
    push cx
    push si

    mov al, PlayerX
    mov PrevPlayerX, al

    mov cx, BulletCount
    mov si, 0
SyncPrevState_Bullets:
    mov al, byte ptr [BulletActive+si]
    mov byte ptr [PrevBulletActive+si], al
    mov al, byte ptr [BulletX+si]
    mov byte ptr [PrevBulletX+si], al
    mov al, byte ptr [BulletY+si]
    mov byte ptr [PrevBulletY+si], al
    inc si
    loop SyncPrevState_Bullets

    mov cx, EnemyCount
    mov si, 0
SyncPrevState_Enemies:
    mov al, byte ptr [EnemyAlive+si]
    mov byte ptr [PrevEnemyAlive+si], al
    mov al, byte ptr [EnemyX+si]
    mov byte ptr [PrevEnemyX+si], al
    mov al, byte ptr [EnemyY+si]
    mov byte ptr [PrevEnemyY+si], al
    inc si
    loop SyncPrevState_Enemies

    pop si
    pop cx
    pop ax
    ret
SyncPrevState endp

DrawPlayer proc near
    push ax
    push bx
    push dx

    mov al, '^'         ; Player character
    mov bl, 0Ah         ; Light Green color attribute
    mov dh, PlayerY
    mov dl, PlayerX
    call PutCharAt

    pop dx
    pop bx
    pop ax
    ret
DrawPlayer endp

DrawBullets proc near
    push ax
    push bx
    push cx
    push dx
    push di

    mov cx, BulletCount
    mov di, 0
DrawBullets_Loop:
    cmp byte ptr [BulletActive+di], 0
    je DrawBullets_Next
    mov al, '|'         ; Bullet character
    mov bl, 0Fh         ; Bright White color
    mov dh, byte ptr [BulletY+di]
    mov dl, byte ptr [BulletX+di]
    call PutCharAt
DrawBullets_Next:
    inc di
    loop DrawBullets_Loop

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret
DrawBullets endp

DrawEnemies proc near
    push ax
    push bx
    push cx
    push dx
    push si

    mov cx, EnemyCount
    mov si, 0
DrawEnemies_Loop:
    cmp byte ptr [EnemyAlive+si], 0
    je DrawEnemies_Next
    mov bl, 0Ch         ; Light Red color
    mov dh, byte ptr [EnemyY+si]
    mov dl, byte ptr [EnemyX+si]
    call DrawEnemySpriteAt
DrawEnemies_Next:
    inc si
    loop DrawEnemies_Loop

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
DrawEnemies endp                

DrawEnemySpriteAt proc near
    ; Draws a 3-character enemy sprite based on animation frame
    push ax
    push si

    mov al, EnemyAnim
    cmp al, 0
    jne DrawEnemySpriteAt_Frame1
    lea si, EnemySprite0    ; Load address of frame 0 ('/X\')
    jmp DrawEnemySpriteAt_Draw
DrawEnemySpriteAt_Frame1:
    lea si, EnemySprite1    ; Load address of frame 1 ('\X/')
DrawEnemySpriteAt_Draw:
    lodsb               ; Load char from [SI] to AL, increment SI
    call PutCharAt
    inc dl
    lodsb
    call PutCharAt
    inc dl
    lodsb
    call PutCharAt

    pop si
    pop ax
    ret
DrawEnemySpriteAt endp
;; ==========================================
;; LOW-LEVEL VIDEO HELPERS
;; ==========================================
ClearScreen proc near
    push ax
    push bx
    push cx
    push dx
    mov ax, 0600h       ; BIOS Scroll Window Up (AL=0 clears entirely)
    mov bh, 07h         ; Fill with light grey on black
    mov cx, 0000h       ; Top-Left corner (0,0)
    mov dx, 184Fh       ; Bottom-Right corner (24,79)
    int 10h
    pop dx
    pop cx
    pop bx
    pop ax
    ret
ClearScreen endp
ClearPlayfield proc near
    ; Same as clear screen but ignores Row 0 (HUD area)
    push ax
    push bx
    push cx
    push dx
    mov ax, 0600h
    mov bh, 07h
    mov ch, 1           ; Start at row 1
    mov cl, 0
    mov dh, 24
    mov dl, 79
    int 10h
    pop dx
    pop cx
    pop bx
    pop ax
    ret
ClearPlayfield endp


SetCursor proc near
    ; Moves hardware cursor to DH (Row), DL (Col)
    push ax
    push bx
    mov ah, 02h         ; BIOS Set Cursor Position
    mov bh, 0           ; Page 0
    int 10h
    pop bx
    pop ax
    ret
SetCursor endp

PutCharAt proc near
    ; Draws character AL in color BL at DH,DL
    push ax
    push bx
    push cx
    push dx
    call SetCursor
    mov ah, 09h         ; BIOS Write Character and Attribute
    mov bh, 0
    mov cx, 1           ; Write it 1 time
    int 10h
    pop dx
    pop cx
    pop bx
    pop ax
    ret
PutCharAt endp


PrintZAt proc near
    ; Prints Null-terminated string at SI to DH,DL
    push ax
    push bx
    push dx
    push si
    call SetCursor
    mov bx, 0007h
PrintZAt_Loop:
    lodsb               ; Load char from [SI] to AL
    cmp al, 0           ; Is it null terminator?
    je PrintZAt_Done
    mov ah, 0Eh         ; BIOS Teletype output
    int 10h
    jmp PrintZAt_Loop
PrintZAt_Done:
    pop si
    pop dx
    pop bx
    pop ax
    ret
PrintZAt endp