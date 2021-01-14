#!/bin/bash

B=${HOME}/lib_renamed
CROSS_COMPILE=/opt/toolchains/zephyr-sdk-0.11.4/arm-zephyr-eabi/bin/arm-zephyr-eabi-
AR=${CROSS_COMPILE}ar
CC="${CROSS_COMPILE}gcc -mfloat-abi=hard -mcpu=cortex-r4f -mfpu=vfpv3-d16"
OBJCOPY=${CROSS_COMPILE}objcopy
READELF=${CROSS_COMPILE}readelf

mkdir ${B}
cd ${B}

rm -f ${B}/*.a
rm -f ${B}/*.o

# Because libstdc++ is compiled with ffunction-sections, there are a bajillion
# .text sections making renaming them all difficult.  So prefix every section
# with .app and then rename .init_array
stl_path=`${CC} -print-file-name=libstdc++.a`
lib_renamed=${B}/`basename ${stl_path} .a`_renamed.a
cp ${stl_path} ${lib_renamed}
${OBJCOPY} --prefix-alloc-sections=.app --strip-debug $lib_renamed
${OBJCOPY} --rename-section .app.init_array=.init_array $lib_renamed

lib_path=`${CC} -print-file-name=libm.a`
lib_renamed=${B}/`basename ${lib_path} .a`_renamed.a
${OBJCOPY} --prefix-alloc-sections=.app ${lib_path} ${lib_renamed}

# Similar for libgcc
lib_path=`${CC} -print-file-name=libgcc.a`
lib_renamed=${B}/`basename ${lib_path} .a`_renamed.a
${OBJCOPY} --prefix-alloc-sections=.app ${lib_path} ${lib_renamed}

${AR} x ${lib_renamed} _udivsi3.o _dvmd_tls.o _aeabi_uldivmod.o _udivmoddi4.o _aeabi_ldivmod.o
${OBJCOPY} --rename-section .app.text=.text _udivsi3.o
${OBJCOPY} --rename-section .app.text=.text _dvmd_tls.o
${OBJCOPY} --rename-section .app.text=.text _aeabi_uldivmod.o
${OBJCOPY} --rename-section .app.text=.text _aeabi_ldivmod.o
${OBJCOPY} --rename-section .app.text=.text --rename-section .app.ARM.exidx=.ARM.exidx _udivmoddi4.o
${AR} r ${lib_renamed} _udivsi3.o _dvmd_tls.o _aeabi_uldivmod.o _udivmoddi4.o _aeabi_ldivmod.o
rm -f _udivsi3.o _dvmd_tls.o _aeabi_uldivmod.o _udivmoddi4.o _aeabi_ldivmod.o

# Most of the stuff we pull in from libc is for engine and supplies so
# these functions can live on spi flash.  The following chunk of scripting
# prefixes all the section names of libc with .app.  It then renames the
# sections used by zephyr back to their original names.  Those sections
# will end up in SRAM since they are used by zephyr.  The sections
# prefixed with .app will reside on spi flash.
lib_path=`${CC} -print-file-name=libc.a`
lib_renamed=${B}/`basename ${lib_path} .a`_renamed.a
${OBJCOPY} --prefix-alloc-sections=.app ${lib_path} ${lib_renamed}

CLIBS="lib_a-strlen.o lib_a-strcmp.o lib_a-memcpy.o" #lib_a-impure.o
${AR} x ${lib_renamed} ${CLIBS}
${OBJCOPY} --rename-section .app.text=.app.text.strlen lib_a-strlen.o
${OBJCOPY} --rename-section .app.text=.app.text.strcmp lib_a-strcmp.o
${OBJCOPY} --rename-section .app.text=.app.text.memcpy lib_a-memcpy.o
#${OBJCOPY} --rename-section .app.data._impure_ptr=.data._impure_ptr --rename-section .app.data.impure_data=.data.impure_data lib_a-impure.o
${AR} r ${lib_renamed} ${CLIBS}
rm -f ${CLIBS}

rm -f ${B}/libc_section_renames
ram_sections="memcmp memcpy memset memmove strncmp strncpy strnlen strcmp strlen strstr strchr strtol _strtol strtoul _strtoul_l _ctype_ __ascii_mbtowc __ascii_wctomb _setlocale abort atoi two_way_long_needle __get_current_locale __get_global_locale critical_factorization"
for section in ${ram_sections}; do
    ${READELF} -SW ${lib_renamed} \
        | grep -e "\[[ ]*[0-9][0-9]*\] \.app\.text\.$section" \
        | awk 'match($0,/\.app\.text\.'$section'[.A-Za-z0-9_]*/) { print substr($0,RSTART,RLENGTH)}' \
        | sort \
        | uniq >> ${B}/libc_section_renames
done

for section in ${ram_sections}; do
    ${READELF} -SW ${lib_renamed} \
        | grep -e "\[[ ]*[0-9][0-9]*\] \.app\.rodata\.$section" \
        | awk 'match($0,/\.app\.rodata\.'$section'[.A-Za-z0-9_]*/) { print substr($0,RSTART,RLENGTH)}' \
        | sort \
        | uniq >> ${B}/libc_section_renames
done

for sec_name in `cat ${B}/libc_section_renames`; do
    ${OBJCOPY} --rename-section $sec_name=${sec_name:4} $lib_renamed
done
