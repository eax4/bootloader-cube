default: assemble qemuemulate

IMGNAME=cube.img
FILENAME=cube.s

assemble: $(FILENAME)
	nasm $< -f bin -o $(IMGNAME)

qemuemulate: $(IMGNAME)
	qemu-system-i386 $<
