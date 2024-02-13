; 76E003 ADC test program: Reads channel 7 on P1.1, pin 14
; This version uses an LED as voltage reference connected to pin 6 (P1.7/AIN0)

$NOLIST
$MODN76E003
$LIST

;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200 ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
	TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))

	TIMER2_RATE   EQU 100     ; 100Hz, for a timer tick of 10ms
TIMER2_RELOAD EQU ((65536-(CLK/(TIMER2_RATE*16))))


ORG 0x0000
	ljmp main

ORG 0x002B
	ljmp Timer2_ISR
		
cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
	LCD_D7 equ P0.3
	PWM_OUT equ P1.0

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
x_backup:	ds 4
y:   ds 4
cold_junc_temp:	ds 4
bcd: ds 5
bcd_backup:	ds 5
VREF: ds 2

; Soldering parameters
soak_temp:	ds 1
soak_time:	ds 1
reflow_temp:	ds 1
reflow_time:	ds 1

state:	ds 1 			; 0 is stopped, 1 is heating, 2 is soaking, 3 is reflowing, 4 is cooling
state_secs:	ds 1
timer_secs:	ds 1
timer_mins:	ds 1

pwm_counter:	ds 1
pwm:	ds 1
	
param:	ds 1 			; Determines which parameter is being edited, in the order above
	
BSEG
mf: dbit 1
	
; Buttons are active low
Select_button:	dbit 1
Down_button:	dbit 1
Up_button:	dbit 1
Start_button:	dbit 1
Second_heating:	dbit 1

$NOLIST
$include(math32.inc)
	$LIST

Celsius_Unit_String:	db 0xDF, 'C ', 0
Stop_State_String:	db 'ST ', 0
Heating_State_String:	db 'HT ', 0
Soaking_State_String:	db 'SK ', 0
Reflow_State_String:	db 'RF ', 0
Cooling_State_String:	db 'CL ', 0

Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in the ISR.  It is bit addressable.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw

	inc pwm_counter
	clr c
	mov a, pwm
	subb a, pwm_counter ; If pwm_counter <= pwm then c=1
	cpl c
	mov PWM_OUT, c
	mov a, pwm_counter
	cjne a, #100, Timer2_ISR_done
	mov pwm_counter, #0

	lcall Read_Temp

	mov a, state

	mov a, state_secs
	add a, #0x01
	da a
	mov state_secs, a

	jz Timer2_ISR_Done
	
Inc_Seconds:
	mov a, timer_secs
	add a, #0x01
	da a
	xrl a, #0x60
	jz Inc_Minutes
	xrl a, #0x60
	mov timer_secs, a
	sjmp Timer2_ISR_done
Inc_Minutes:
	clr a
	mov timer_secs, a
	mov a, timer_mins
	add a, #0x01
	da a
	mov timer_mins, a
Timer2_ISR_Done:
	pop psw
	pop acc
	reti
	
Init_All:
	; Configure all the pins for bidirectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00
	
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
	setb TR1
	
	; Using timer 0 for delay functions.  Initialize here:
	clr	TR0 ; Stop timer 0
	orl	CKCON,#0x08 ; CLK is the input for timer 0
	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer

				; Using timer 2 for keeping time.
	mov T2CON, #0
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)

	orl T2MOD, #0b1010_0000
	mov RCMP2H, #high(TIMER2_RELOAD)
	mov RCMP2L, #low(TIMER2_RELOAD)
	mov pwm_counter, #0
	; Init two millisecond interrupt counter.
	clr a
	; Enable the timer and interrupts
	orl EIE, #0x80 ; Enable timer 2 interrupt ET2=1
	
	; Initialize the pins used by the ADC (P1.1, P1.7) as input.
	orl	P1M1, #0b10000010
	anl	P1M2, #0b01111101
	
	; Initialize and start the ADC:
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x07 ; Select channel 7
	; AINDIDS select if some pins are analog inputs or digital I/O:
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b10000011 ; Activate AIN0 and AIN7 analog inputs
	orl ADCCON1, #0x01 ; Enable ADC

	setb EA
	
	ret
	
wait_1ms:
	clr	TR0 ; Stop timer 0
	clr	TF0 ; Clear overflow flag
	mov	TH0, #high(TIMER0_RELOAD_1MS)
	mov	TL0,#low(TIMER0_RELOAD_1MS)
	setb TR0
	jnb	TF0, $ ; Wait for overflow
	ret

putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
	ret

; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret

put_x:
	mov a, x+3
	lcall putchar
	mov a, x+2
	lcall putchar
	mov a, x+1
	lcall putchar
	mov a, x+0
	lcall putchar
	mov a, soak_temp
	lcall putchar
	mov a, soak_time
	lcall putchar
	mov a, reflow_temp
	lcall putchar
	mov a, reflow_time
	lcall putchar
	mov a, state
	lcall putchar
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	ret

; Wait the number of miliseconds in R2
waitms:
	lcall wait_1ms
	djnz R2, waitms
	ret

read_pbs:
	setb P1.5
	setb Select_button
	setb Down_button
	setb Up_button
	setb Start_button
	setb P0.0
	setb P0.1
	setb P0.2
	setb P0.3

	clr P0.3
	jb P1.5, check_up
	jnb P1.5, $
	clr Select_button
check_up:
	setb P0.3
	clr P0.1
	jb P1.5, check_down
	jnb P1.5, $
	clr Up_button
check_down:
	setb P0.1
	clr P0.2
	jb P1.5, check_start
	jnb P1.5, $
	clr Down_button
check_start:
	setb P0.1
	clr P0.0
	jb P1.5, read_pbs_ret
	jnb P1.5, $
	clr Start_button
read_pbs_ret:
	ret
	
	
display_units:
	Send_Constant_String(#Celsius_Unit_String)
	ret

display_time:
	Display_BCD(timer_mins)
	Display_char(#':')
	Display_BCD(timer_secs)
	ret

pop_x:
	mov x+0, x_backup+0
	mov x+1, x_backup+1
	mov x+2, x_backup+2
	mov x+3, x_backup+3
	ret

push_x:
	mov x_backup+0, x+0
	mov x_backup+1, x+1
	mov x_backup+2, x+2
	mov x_backup+3, x+3
	ret
	
pop_BCD:
	mov bcd+0, bcd_backup+0
	mov bcd+1, bcd_backup+1
	mov bcd+2, bcd_backup+2
	mov bcd+3, bcd_backup+3
	mov bcd+4, bcd_backup+4
	ret

push_BCD:
	mov bcd_backup+0, bcd+0
	mov bcd_backup+1, bcd+1
	mov bcd_backup+2, bcd+2
	mov bcd_backup+3, bcd+3
	mov bcd_backup+4, bcd+4
	ret
	
; We can display a number any way we want.  In this case with
; four decimal places.
Display_first_row:
	Set_Cursor(1, 1)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_char(#'.')
	Display_BCD(bcd+0)
	lcall display_units
	lcall display_time
	ret

Display_second_row:
	Set_Cursor(2, 1)
	mov a, state
	cjne a, #0x00, display_heating_state
	Send_Constant_String(#Stop_State_String)
	ljmp Display_second_row_b
display_heating_state:
	cjne a, #0x01, display_soaking_state
	Send_Constant_String(#Heating_State_String)
	ljmp Display_second_row_b
display_soaking_state:
	cjne a, #0x02, display_reflow_state
	Send_Constant_String(#Soaking_State_String)
	ljmp Display_second_row_b
display_reflow_state:
	cjne a, #0x03, display_cooling_state
	Send_Constant_String(#Reflow_State_String)
	ljmp Display_second_row_b
display_cooling_state:
	Send_Constant_String(#Cooling_State_String)
Display_second_row_b:
	Display_char(#'1')
	Display_BCD(soak_temp)
	Display_char(#' ')
	Display_BCD(soak_time)
	Display_char(#' ')
	Display_char(#'2')
	Display_BCD(reflow_temp)
	Display_char(#' ')
	Display_BCD(reflow_time)
	ret
	
	

Read_ADC:
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRL
    anl a, #0x0f
    mov R0, a
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, R0
    mov R0, A	
	ret
	
convert_temp:
	load_y(27315) 	
	lcall sub32
	ret

cycle_param:
	mov a, param
	add a, #0x01
	cjne a, #0x04, cycle_param_ret
	clr a
cycle_param_ret:
	mov param, a
	ret

param_down:
	mov a, param
	cjne a, #0x00, soak_time_down
	mov a, soak_temp
	add a, #0x99
	da a
	mov soak_temp, a
	ljmp param_down_ret
soak_time_down:
	cjne a, #0x01, reflow_temp_down
	mov a, soak_time
	add a, #0x99
	da a
	mov soak_time, a
	ljmp param_down_ret
reflow_temp_down:
	cjne a, #0x02, reflow_time_down
	mov a, reflow_temp
	jnz reflow_temp_down_b
	mov reflow_temp, #0x40
	ljmp param_down_ret
reflow_temp_down_b:	
	add a, #0x99
	da a
	mov reflow_temp, a
	ljmp param_down_ret
reflow_time_down:
	mov a, reflow_time
	add a, #0x99
	da a
	mov reflow_time, a
param_down_ret:
	ret

param_up:
	mov a, param
	cjne a, #0x00, soak_time_up
	mov a, soak_temp
	add a, #0x01
	da a
	mov soak_temp, a
	ljmp param_up_ret
soak_time_up:
	cjne a, #0x01, reflow_temp_up
	mov a, soak_time
	add a, #0x01
	da a
	mov soak_time, a
	ljmp param_up_ret
reflow_temp_up:	
	cjne a, #0x02, reflow_time_up
	mov a, reflow_temp
	xrl a, #0x40
	jnz reflow_temp_up_b
	mov reflow_temp, #0x00
	ljmp param_up_ret
reflow_temp_up_b:
	xrl a, #0x40
	add a, #0x01
	da a
	mov reflow_temp, a
	ljmp param_up_ret
reflow_time_up:
	mov a, reflow_time
	add a, #0x01
	da a
	mov reflow_time, a
param_up_ret:
	ret

toggle_start:
	; State changes here - Turn on buzzer
	mov a, state
	jz toggle_start_b
	mov state, #0x00
	ret
toggle_start_b:
	mov state, #0x01
	ret
	
	
main:
	mov sp, #0x7f
	lcall Init_All
	lcall LCD_4BIT

	mov timer_secs, #0
	mov timer_mins, #0 
	mov state, #0

	mov soak_temp, #0x60
	mov soak_time, #0x70
	mov reflow_temp, #0x20
	mov reflow_time, #0x30

	mov param, #0x00

	clr Second_heating

	mov pwm, #0
	mov pwm_counter, #0

	setb TR2
	

check_state:
	mov a, state
	cjne a, #0x00, check_state_b
	ljmp stopped_loop
check_state_b:
	cjne a, #0x01, check_state_c
	ljmp heating_loop
check_state_c:
	cjne a, #0x02, check_state_d
	ljmp soaking_loop
check_state_d:
	cjne a, #0x03, check_state_e
	ljmp reflow_loop
check_state_e:
	ljmp cooling_loop

stopped_loop:
	mov timer_secs, #0x00
	mov timer_mins, #0x00
	mov pwm, #0
	lcall read_pbs
	jb Select_button, stopped_loop_b
	lcall cycle_param
stopped_loop_b:
	jb Down_button, stopped_loop_c
	lcall param_down
stopped_loop_c:
	jb Up_button, stopped_loop_d
	lcall param_up
stopped_loop_d:
	jb Start_button, stopped_loop_e
	mov state_secs, #0x00
	lcall toggle_start
stopped_loop_e:
	lcall Display_first_row
	lcall Display_second_row
	ljmp check_state

heating_loop:
	mov pwm, #100
	lcall read_pbs
	jb Start_button, heating_loop_b
	lcall toggle_start
heating_loop_b:
	mov a, state_secs
	cjne a, #0x60, heating_loop_c
	clr TR2
	lcall pop_x
	load_y(100)
	lcall div32
	clr a
	mov a, x
	clr c
	subb a, #50
	setb TR2
	jnc heating_loop_g
	lcall toggle_start 
heating_loop_c:
	clr TR2
	load_y(100)
	lcall pop_x
	lcall div32
	clr a
	mov a, x
	lcall push_BCD
	jb Second_heating, heating_loop_d
	load_x(100)
	lcall hex2bcd
	mov bcd+0, soak_temp
	sjmp heating_loop_e
heating_loop_d:
	load_x(200)
	lcall hex2bcd
	mov bcd+0, reflow_temp
heating_loop_e:	
	lcall bcd2hex
	lcall pop_BCD
	clr c
	subb a, x
	setb TR2
	jc heating_loop_g
	; State changes here - turn on buzzer
	mov state_secs, #0x00
	jb Second_heating, heating_loop_f
	mov state, #0x02
	sjmp heating_loop_g
heating_loop_f:
	mov state, #0x03
heating_loop_g:
	lcall Display_first_row
	lcall Display_second_row
	ljmp check_state

soaking_loop:
	mov pwm, #0
	lcall read_pbs
	jb Start_button, soaking_loop_b
	lcall toggle_start
soaking_loop_b:
	mov a, state_secs
	xrl a, soak_time
	jnz soaking_loop_c
	; State changes here - turn on buzzer
	setb Second_heating
	mov state, #0x01
soaking_loop_c:	
	lcall Display_first_row
	lcall Display_second_row
	ljmp check_state

reflow_loop:
	mov pwm, #20
	lcall read_pbs
	jb Start_button, reflow_loop_b
	lcall toggle_start
reflow_loop_b:
	mov a, state_secs
	xrl a, reflow_time
	jnz reflow_loop_c
	; State changes here- turn on buzzer
	mov state, #0x04
reflow_loop_c:
	lcall Display_first_row
	lcall Display_second_row
	ljmp check_state

cooling_loop:
	mov pwm, #0
	lcall read_pbs
	jb Start_button, cooling_loop_b
	lcall toggle_start
cooling_loop_b:
	clr TR2
	load_y(100)
	lcall pop_x
	lcall div32
	clr a
	mov a, x
	lcall push_BCD
	load_x(0)
	lcall hex2bcd
	mov bcd+0, #0x60
	lcall bcd2hex
	lcall pop_BCD
	clr c
	subb a, x
	setb TR2
	jnc cooling_loop_c
	lcall toggle_start
cooling_loop_c:
	lcall Display_first_row
	lcall Display_second_row
	ljmp check_state
	
Read_Temp:
	; Read the 4.096V voltage reference connected to AIN0 on pin 6
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x00 ; Select channel 0

	lcall Read_ADC
	; Save result for later use
	mov VREF+0, R0
	mov VREF+1, R1

	; Read the signal connected to AIN7
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x07 ; Select channel 7
	lcall Read_ADC
    
    ; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	; Pad other bits with zero
	mov x+2, #0
	mov x+3, #0
	Load_y(41132) ; The MEASURED reference voltage 4.1132V, with 4 decimal places
	lcall mul32
	; Retrive the ADC LED value
	mov y+0, VREF+0
	mov y+1, VREF+1
	; Pad other bits with zero
	mov y+2, #0
	mov y+3, #0
	lcall div32

	load_y(800) 		; Adjustment based on thermostat readings
	lcall add32

	lcall convert_temp

	mov cold_junc_temp+0, x+0
	mov cold_junc_temp+1, x+1
	mov cold_junc_temp+2, x+2
	mov cold_junc_temp+3, x+3

	anl ADCCON0, #0xF0
	orl ADCCON0, #0x01 ; Select channel 1
	lcall Read_ADC

	mov x+0, R0
	mov x+1, R1
	mov x+2, #0
	mov x+3, #0

	Load_y(41132)
	lcall mul32
	mov y+0, VREF+0
	mov y+1, VREF+1
	mov y+2, #0
	mov y+3, #0
	lcall div32

	load_y(7391) 		; Amplifier gain means 73.91 degrees C / Volt
	lcall mul32
	load_y(10000)
	lcall div32

	mov y+0, cold_junc_temp+0
	mov y+1, cold_junc_temp+1
	mov y+2, cold_junc_temp+2
	mov y+3, cold_junc_temp+3
	lcall add32

	; Convert to BCD and display
	lcall hex2bcd

	lcall put_x
	lcall push_x
	
	ret
END
