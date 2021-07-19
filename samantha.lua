local te = require 'textentry'
local screen_dirty = true
local alt = false
local recorded = false
local primed = false
local primed_flash = false
local recording = false
local quantized = true
local playing = false
local text_display_time = 2.0
local text_display = ''
local start_time = nil
local current_position = 0
local q_div_table = {nil, 0.03125, 0.0625, 0.125, 0.25, 0.5, 1, 2, 4}
local max_len_table = {nil, 0.5, 1, 2, 4, 6, 8}
local max_len = nil
local last_saved_name = ''

local screen_x_padding = 4
local screen_y_padding = 4
local screen_y_centered = 21

local function reset_loop()
  softcut.buffer_clear(1)
  params:set("sample", "-")
  params:set("loop_start", 0)
  params:set("loop_end", 350.0)
  softcut.position(1, 0)
  current_position = 0
end


local function set_loop_start(v)
  v = util.clamp(v, 0, params:get("loop_end") - .01)
  softcut.loop_start(1, v)
end


local function set_loop_end(v)
  v = util.clamp(v, params:get("loop_start") + .01, 350.0)
  softcut.loop_end(1, v)
end


local function start_recording()
	reset_loop()
	softcut.rec(1, 1)
	recording = true
	start_time = util.time()
end


local function stop_recording()
	params:set("loop_end", current_position)
	softcut.rec(1,0)
	softcut.position(1, 0)
	recording = false
	playing = true
	softcut.play(1, 1)
end


function init()
  -- softcut setup
  audio.level_cut(1)
  audio.level_adc_cut(1)
  audio.level_eng_cut(1)
  softcut.level(1,1)
  softcut.level_slew_time(1,0.1)
  softcut.level_input_cut(1, 1, 1.0)
  softcut.level_input_cut(2, 1, 1.0)
  softcut.pan(1, 0.5)
  softcut.play(1, 0)
  softcut.rate(1, 1)
  softcut.rate_slew_time(1,0.1)
  softcut.loop_start(1, 0)
  softcut.loop_end(1, 350)
  softcut.loop(1, 1)
  softcut.fade_time(1, 0.1)
  softcut.rec(1, 0)
  softcut.rec_level(1, 1)
  softcut.pre_level(1, 1)
  softcut.position(1, 0)
  softcut.buffer(1,1)
  softcut.enable(1, 1)
  softcut.filter_dry(1, 1)


	-- set up input poll
	p_input_level = poll.set("amp_in_l")
	p_input_level.callback = function(v)
		if v > params:get("input_trigger_amp") then
			p_input_level:stop()
			start_recording()
			primed = false
		end
	end
	p_input_level.time = 0.02

  -- load a sample
  params:add_file("sample", "sample")
  -- params:set_action("sample", function(file) load_sample(file) end)
  -- sample start controls
  params:add_control("loop_start", "loop start", controlspec.new(0.0, 349.99, "lin", .01, 0, "secs"))
  -- params:set_action("loop_start", function(x) set_loop_start(x) end)
  -- sample end controls
  params:add_control("loop_end", "loop end", controlspec.new(.01, 350, "lin", .01, 350, "secs"))
  -- params:set_action("loop_end", function(x) set_loop_end(x) end)
	
  -- quantize
  params:add_option('q_div', 'q div', {'off', '1/32', '1/16', '1/8', '1/4', '1/2', '1', '2', '4'}, 5)
  -- params:set_action("q_div", function(x) quantize(x) end)

  -- max length
  params:add_option('auto_len', "auto length", {'off', '1/2', '1', '2', '4', '6', '8'}, 1)
  -- params:set_action("auto_len", function(x) set_max_len(x) end)

  -- input trigger db
  local max_len_cs = controlspec.def{
    min=0.00,
    max=5.0,
    warp='lin',
    step=0.01, -- calc real time chunks based on quantize setting and bpm
    default=0,
    quantum=0,
    wrap=false,
    units='sec'
  }
  
  local amp_cs = controlspec.AMP
  amp_cs.default = 0.5
  params:add_control("input_trigger_amp","input trigger",amp_cs)


  -- screen metro
  local screen_timer = metro.init()
  screen_timer.time = 1/15
  screen_timer.event = function() redraw() end
  screen_timer:start()
  
  -- rec armed metro
  armed_timer = metro.init()
  armed_timer.time = 1/2.5
  armed_timer.event = function() primed_flash = not primed_flash end
  
  
  -- local screen_refresh_metro = metro.init()
  -- screen_refresh_metro.event = function()
  --   screen_update()
  --   if screen_dirty then
  --     screen_dirty = false
  --     redraw()
  --   end
  -- end

  -- softcut phase poll
  softcut.phase_quant(1, .01)
  softcut.event_phase(update_positions)
  softcut.poll_start_phase()
end

function key(n, z)
  -- set alt
	if n == 1 then
  	alt = z == 1 and true or false
	end

	-- K2
  if n == 2 and z == 1 then
		if recording == false then
			if alt then
			  primed = true
			  -- TODO: pause playback
			  armed_timer:start()
			  p_input_level:start()
			  alt = not alt
			else
			  p_input_level:stop()
			  armed_timer:stop()
			  primed = false
				start_recording();
			end
		else
			stop_recording();
		end
		
	-- K3
  elseif n == 3 and z == 1 then
    if alt then
			-- save sample
      te.enter(write_buffer, increment_name(last_saved_name), 'Save Sample As: ')
      alt = not alt
			text_display = "saved " .. last_saved_name .. ".wav"
    else
      if primed then
        armed_timer:stop()
        p_input_level:stop()
        primed = false
      elseif recording then
        -- do nothing
      else
        if playing == true then
          softcut.play(1, 0)
          playing = false
        else
          softcut.position(1, 0)
          softcut.play(1, 1)
          playing = true
        end
      end
    end
  end
  screen_dirty = true
end


function enc(n, d)
  if alt then
		if n == 1 then
			params:delta("q_div", d)
    elseif n == 2 then
      params:delta("input_trigger_amp", d)
    elseif n == 3 then
      params:delta("auto_len", d)
    end
  else
    if n == 1 then
			-- better way to combine?
			-- todo: add check for quantization later
			-- check to see if one parameter is at its highest possible value before changing either
			-- or give up on this feature and edit BPM instead (easier lol)
			
			-- params:delta("loop_start", d * .005)
			-- params:delta("loop_end", d * .005)
		elseif n == 2 then
      params:delta("loop_start", d * .005)
    elseif n == 3 then
      params:delta("loop_end", d * .005)
    end
  end
  screen_dirty = true
end


function redraw()
  screen.aa(0)
  screen.clear()
  screen.level(3)
  screen.move(screen_x_padding, screen_y_padding + 5)
  screen.text(params:get("clock_tempo") ..  " BPM")
  screen.move(128 - screen_x_padding, screen_y_padding + 5)
  if alt then
    screen.level(15)
  end
  screen.text_right("Q " .. params:string("q_div"))
  
  screen.level(1)
  screen.rect(56, 14, 17, 17)
  screen.stroke()
  
  
  if recording or primed or not recorded then
    if recording then
      screen.level(15)
    elseif primed then
      if primed_flash then
        screen.level(15)
      else
        screen.level(3)
      end
    else
      screen.level(3)
    end
    screen.circle(64, screen_y_centered+1, 6)
    screen.fill()
  elseif playing then
    -- draw triangle
  elseif paused then
    -- draw bars
  end


  screen.level(3)
  screen.move(64, screen_y_centered + 21)
  if not recorded then
    screen.text_center("-")
  elseif recording then
    screen.text_center("end : " .. string.format("%.2f", current_position))
  else
    screen.text_center("todo: loop length")
  end
  

  
  screen.move(64, screen_y_centered + 21 + 9)
  if not recorded or not quantized then
    screen.text_center("-")
  elseif recording then
    -- quantize this
    screen.text_center("Q end : " .. string.format("%.2f", current_position))
  else
    screen.text_center("todo: Q loop length")
  end

  
  screen.move(screen_x_padding, 64 - screen_y_padding)  
  screen.level(15)
  if recording then
    screen.text("LOOP")
  else
    if alt then
      screen.text("ARM")
      -- screen.text("Q " .. params:get("clock_tempo") .. "/" .. params:get("quantize_div"))
    elseif primed then
      if primed_flash then
        screen.level(15)
      else
        screen.level(3)
      end
      screen.text("REC")
    else
      screen.text("REC")
    end
  end
  
  
  screen.move(128 - screen_x_padding, 64 - screen_y_padding)
  if recording then
    screen.level(3)
    screen.text_right("-")
  elseif primed then
    screen.level(15)
    screen.text_right("CANCEL")
  elseif alt then
    if recorded then
      screen.level(15)
      screen.text_right("SAVE")
    else
      screen.level(3)
      screen.text_right("-")
    end
  elseif recorded then
    if playing then
      screen.text_right("STOP")
    else
      screen.text_right("PLAY")
    end
  else
    screen.level(3)
    screen.text_right("-")
  end
    
  screen.move(screen_x_padding, 64 - screen_y_padding - 9)
  if alt then
    screen.level(15)
    screen.text(string.format("%.2f", params:get("input_trigger_amp")))
    screen.move(128 - screen_x_padding, 51)
    screen.text_right(params:string("auto_len"))
  else
    if recorded then
      screen.level(15)
      screen.text("▶ " .. string.format("%.2f", params:get("loop_start")))
      screen.move(120, 51)
      screen.text_right(string.format("%.2f", params:get("loop_end")) .. " ◀")
    else
      screen.level(3)
      screen.text("▶ -")
     screen.move(128 - screen_x_padding, 64 - screen_y_padding - 9)
     screen.text_right("- ◀")
    end
  end
  
  screen.move(64, 54)
  screen.level(4)
  if util.time() - text_display_time <= 1.0 then
    screen.text_center(text_display)
	end
  screen.update()
end
