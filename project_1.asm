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


ORG 0x0000
	ljmp main
	
cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3	

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
cold_junc_temp:	ds 4
bcd: ds 5
VREF: ds 2

; Soldering parameters
soak_temp:	ds 1
soak_time:	ds 1
reflow_temp:	ds 1
reflow_time:	ds 1

state:	ds 1 			; 0 is stopped, 1 is heating, 2 is soaking, 3 is reflowing, 4 is cooling 
timer_secs:	ds 1
timer_mins:	ds 1

param:	ds 1 			; Determines which parameter is being edited, in the order above
	
BSEG
mf: dbit 1
; Buttons are active low
Select_button:	dbit 1
Down_button:	dbit 1
Up_button:	dbit 1
Start_button:	dbit 1

$NOLIST
$include(math32.inc)
	$LIST

Celsius_Unit_String:	db 0xDF, 'C ', 0
Stop_State_String:	db 'ST ', 0
Heating_State_String:	db 'HT ', 0
Soaking_State_String:	db 'SK ', 0
Reflow_State_String:	db 'RF', 0
	
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
	clr a
	mov a, #240
	anl a, bcd+2
	rr a
	rr a
	rr a
	rr a
	add a, #'0'
	lcall putchar
	clr a
	mov a, #15
	anl a, bcd+2
	add a, #'0'
	lcall putchar
	clr a
	mov a, #240
	anl a, bcd+1
	rr a
	rr a
	rr a
	rr a
	add a, #'0'
	lcall putchar
	clr a
	mov a, #15
	anl a, bcd+1
	add a, #'0'
	lcall putchar
	clr a
	mov a, #240
	anl a, bcd+0
	rr a
	rr a
	rr a
	rr a
	add a, #'0'
	lcall putchar
	clr a
	mov a, #15
	anl a, bcd+0
	add a, #'0'
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
	clr Select_button
check_up:
	setb P0.3
	clr P0.2
	jb P1.5, check_down
	clr Up_button
check_down:
	setb P0.2
	clr P0.1
	jb P1.5, check_start
	clr Down_button
check_start:
	setb P0.1
	clr P0.0
	jb P1.5, read_pbs_ret
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
	Send_Constant_String(#Reflow_State_String)
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
	jnz reflow_temp_up_b
	mov reflow_temp, #0x40
	ljmp param_up_ret
reflow_temp_up_b:	
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

check_state:
	mov a, state
	cjne a, #0x00, check_state_b
	ljmp stopped_loop
check_state_b:
	sjmp check_state

stopped_loop:
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
	lcall toggle_start
stopped_loop_e:	
	lcall Read_Temp
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
	lcall Display_first_row

	lcall put_x
	
	; Wait 500 ms between conversions
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	
	ret
END
