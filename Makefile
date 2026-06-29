ASM      = nasm
LD       = ld
ASMFLAGS = -f elf64
TARGET   = http_server

all: $(TARGET)

$(TARGET): $(TARGET).o
	$(LD) -o $@ $<

$(TARGET).o: $(TARGET).asm
	$(ASM) $(ASMFLAGS) -o $@ $<

clean:
	rm -f $(TARGET).o $(TARGET)

.PHONY: all clean
