# BeagleV-Fire Boot Roadmap for Claudia

## Overview
BeagleV-Fire is a RISC-V development board featuring the PolarFire SoC with 4x U54 cores and 1x E51 monitor core. This roadmap outlines the steps needed to port Claudia from QEMU to real hardware.

## Phase 1: Hardware Analysis & Prerequisites (1-2 weeks)

### 1.1 BeagleV-Fire Specifications
- **SoC**: Microchip PolarFire MPFS250T
- **CPU**: 1x E51 (Monitor) + 4x U54 (Application) cores
- **RAM**: 2GB DDR4
- **Boot**: SPI Flash, SD Card, eMMC options
- **UART**: Multiple UART interfaces
- **Interrupts**: PLIC + CLINT

### 1.2 Required Documentation
- [ ] PolarFire SoC Technical Reference Manual
- [ ] BeagleV-Fire Board Schematic
- [ ] Hart Software Services (HSS) documentation
- [ ] Memory map specification

### 1.3 Development Environment
- [ ] Setup hardware debugger (OpenOCD/JTAG)
- [ ] Cross-compilation toolchain verification
- [ ] Serial console setup (115200 8N1)

## Phase 2: Bootloader Integration (2-3 weeks)

### 2.1 Understanding Boot Flow
BeagleV-Fire boot sequence:
1. **E51 Core**: Executes Hart Software Services (HSS) from eNVM
2. **HSS**: Initializes DDR, loads next stage from SD/eMMC
3. **U-Boot**: Secondary bootloader (optional)
4. **Payload**: Our kernel

### 2.2 HSS Payload Format
- [ ] Create HSS-compatible payload wrapper
- [ ] Add device tree support (HSS passes DTB)
- [ ` Build payload generator tool

### 2.3 Minimal Boot Code
```zig
// kernel/arch/riscv/beaglev_entry.S
- Receive DTB pointer from HSS
- Setup initial stack
- Clear BSS
- Jump to Zig init code
```

## Phase 3: Hardware Abstraction Layer (3-4 weeks)

### 3.1 Memory Map Adaptation
Current QEMU memory map vs BeagleV-Fire:
```
QEMU:                  BeagleV-Fire:
0x80000000 - RAM       0x80000000 - DDR (2GB)
0x10000000 - UART      0x20100000 - MMUART0
0x0C000000 - PLIC      0x0C000000 - PLIC (same!)
```

### 3.2 UART Driver
- [ ] Port UART from NS16550 (QEMU) to PolarFire MMUART
- [ ] Update MMIO addresses
- [ ] Handle different clock frequencies

### 3.3 Interrupt Controller
- [ ] Verify PLIC compatibility
- [ ] Add CLINT support for timer interrupts
- [ ] Multi-hart interrupt routing

### 3.4 Timer Support
- [ ] Implement CLINT timer driver
- [ ] Add RTC support (if available)
- [ ] Calibrate timing loops

## Phase 4: Multi-Core Support (2-3 weeks)

### 4.1 Hart Management
- [ ] Detect available harts (4x U54)
- [ ] Park secondary harts during boot
- [ ] Implement inter-hart communication

### 4.2 SMP Considerations
- [ ] Add atomic operations
- [ ] Cache coherency handling
- [ ] Per-hart data structures

## Phase 5: Storage Support (3-4 weeks)

### 5.1 SD Card Driver
- [ ] Implement basic SD/MMC controller driver
- [ ] Add block device abstraction
- [ ] Port SimpleFS to use block device

### 5.2 Persistent Storage
- [ ] Replace RAM disk with SD card storage
- [ ] Implement write support
- [ ] Add filesystem cache

## Phase 6: Device Tree Integration (1-2 weeks)

### 6.1 DTB Parser Enhancement
- [ ] Extend current DTB parser
- [ ] Parse memory regions
- [ ] Discover UART addresses
- [ ] Find interrupt mappings

### 6.2 Dynamic Configuration
- [ ] Remove hardcoded addresses
- [ ] Use DTB for all hardware config
- [ ] Support different board revisions

## Phase 7: Testing & Optimization (2-3 weeks)

### 7.1 Hardware-Specific Testing
- [ ] Memory stress tests
- [ ] Interrupt latency measurement
- [ ] Multi-core synchronization tests
- [ ] Power management testing

### 7.2 Performance Optimization
- [ ] Enable caches (I-cache, D-cache)
- [ ] Optimize critical paths
- [ ] Profile and tune

### 7.3 Stability
- [ ] Long-running tests
- [ ] Error recovery
- [ ] Watchdog implementation

## Phase 8: Additional Hardware Support (Optional)

### 8.1 Ethernet (4-6 weeks)
- [ ] Cadence GEM driver
- [ ] Network stack integration
- [ ] Basic TCP/IP

### 8.2 USB Support (6-8 weeks)
- [ ] USB controller driver
- [ ] USB mass storage
- [ ] USB serial console

### 8.3 GPIO & I2C (2-3 weeks)
- [ ] GPIO driver for LEDs/buttons
- [ ] I2C for peripherals
- [ ] SPI for additional storage

## Implementation Order & Time Estimates

### Minimum Viable Product (8-10 weeks)
1. **Weeks 1-2**: Hardware analysis, documentation
2. **Weeks 3-4**: HSS payload, basic boot
3. **Weeks 5-6**: UART working, early console
4. **Weeks 7-8**: Interrupt controller, timer
5. **Weeks 9-10**: Single-core userland execution

### Full Port (16-20 weeks)
- Add multi-core support
- Add SD card storage
- Complete device tree support
- Optimize performance

## Critical Path Items

1. **UART Driver** - Without console output, debugging is impossible
2. **HSS Payload Format** - Must boot correctly from HSS
3. **Memory Map** - Must match hardware exactly
4. **Interrupt Controller** - Required for any I/O

## Known Challenges

1. **Documentation**: PolarFire SoC docs are extensive but complex
2. **Boot Flow**: HSS adds complexity vs direct boot
3. **Multi-Core**: E51 monitor core requires special handling
4. **Timing**: Real hardware timing differs from QEMU

## Testing Strategy

### Phase Testing
- After each phase, verify functionality
- Keep QEMU support for comparison
- Use JTAG debugger extensively

### Test Programs
1. **Hello World** - UART output only
2. **Memory Test** - Verify RAM access
3. **Interrupt Test** - Timer and UART interrupts
4. **Shell** - Full userland with commands
5. **Stress Test** - Multi-process workload

## Success Criteria

- [ ] Boots from SD card via HSS
- [ ] Serial console functional
- [ ] Can run shell and execute commands
- [ ] Stable operation for >1 hour
- [ ] All existing QEMU features work

## Resources

- [BeagleV-Fire Documentation](https://docs.beagleboard.org/latest/boards/beaglev-fire/)
- [PolarFire SoC Documentation](https://www.microchip.com/en-us/products/fpgas-and-plds/system-on-chip-fpgas/polarfire-soc-fpgas)
- [Hart Software Services](https://github.com/polarfire-soc/hart-software-services)
- [BeagleV-Fire Linux Port](https://github.com/linux4microchip/linux) (reference)