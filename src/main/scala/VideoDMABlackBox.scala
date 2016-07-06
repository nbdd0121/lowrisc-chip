package lowrisc_chip

import Chisel._

class VideoDMABlackBox() extends BlackBox() {
	val io = new Bundle {
		val clk         = Bool(INPUT)
		val rst         = Bool(INPUT)

		val fetch_data  = Bool(OUTPUT)
		val read_from   = Bits(INPUT, width = 16)
		val length_data = Bits(INPUT, width = 16)
		val write_to    = Bits(INPUT, width = 18)
		val rd_en       = Bool(INPUT)

		val videomem_rddata = Bits(OUTPUT, width = 32)

		val vga_red    = Bits(OUTPUT, width = 4)
		val vga_green  = Bits(OUTPUT, width = 4)
		val vga_blue   = Bits(OUTPUT, width = 4)
		val vga_hsync  = Bool(OUTPUT)
		val vga_vsync  = Bool(OUTPUT)
	}

	renameClock(Driver.implicitClock, "clk") 
	renameReset("rst")

	moduleName = "video_dma_controller"
}