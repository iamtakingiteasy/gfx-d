#! /usr/bin/env python3
"""
    Vulkan D bindings generator.
    Reads Vulkan XML API definition to produce the D bindings code.
    Also depends on the python scripts of Vulkan-Docs.
"""

from reg import Registry
from generator import OutputGenerator, GeneratorOptions, noneStr
import xml.etree.ElementTree as etree
from itertools import islice
import re
from enum import Enum, auto

# General utility

class Sect(Enum):
    GLOBAL_DEF      = auto()
    BASETYPE        = auto()
    CONST           = auto()
    HANDLE          = auto()
    FUNCPTR         = auto()
    ENUM            = auto()
    STRUCT          = auto()
    CMD             = auto()

class SourceFile(object):
    '''
    buffer to append code in various sections of a file
    in any order
    '''

    _one_indent_level = '    '

    class _Section:
        def __init__(self, sect):
            self.sect = sect
            self.lines = []
            self.indent = 0

    def __init__(self, outFile):
        self._sections = {}
        for sect in Sect:
            self._sections[sect] = SourceFile._Section(sect)

        self._sect = Sect.GLOBAL_DEF
        self._section = self._sections[Sect.GLOBAL_DEF]
        self._outFile = outFile

    @property
    def section(self):
        return self._sect

    @section.setter
    def section(self, section):
        '''
        Set the section of the file where to append code.
        Allows to make different sections in the file to append
        to in any order
        '''
        self._sect = section
        self._section = self._sections[section]


    def indent_block(self):
        class Indenter(object):
            def __init__(self, sf):
                self.sf = sf
            def __enter__(self):
                self.sf.indent()
            def __exit__(self, type, value, traceback):
                self.sf.unindent()
        return Indenter(self)

    def indent(self):
        '''
        adds one level of indentation to the current section
        '''
        self._section.indent += 1

    def unindent(self):
        '''
        removes one level of indentation to the current section
        '''
        assert self._section.indent > 0, "negative indent"
        self._section.indent -= 1

    def __call__(self, fmt="", *args):
        '''
        Append a line to the file at in its current section and
        indentation of the current section
        '''
        indent = SourceFile._one_indent_level * self._section.indent
        self._section.lines.append(indent + (fmt % args))


    def writeOut(self):
        for sect in Sect:
            for line in self._sections[sect].lines:
                print(line.rstrip(), file=self._outFile)


# D specific utilities

re_single_const = re.compile(r"^const\s+(.+)\*\s*$")
re_double_const = re.compile(r"^const\s+(.+)\*\s+const\*\s*$")
re_funcptr = re.compile(r"^typedef (.+) \(VKAPI_PTR \*$")

dkeywords = [ "module" ]

def convertDTypeConst( typ ):
    """
    Converts C const syntax to D const syntax
    """
    doubleConstMatch = re.match( re_double_const, typ )
    if doubleConstMatch:
        return "const({}*)*".format( doubleConstMatch.group( 1 ))
    else:
        singleConstMatch = re.match( re_single_const, typ )
        if singleConstMatch:
            return "const({})*".format( singleConstMatch.group( 1 ))
    return typ

def makeDParamType(param):
    def makePart(part):
        return noneStr(part).replace("struct ", "").strip().replace("const", "const ")

    typeStr = makePart(param.text)
    for elem in param:
        if elem.tag != "name":
            typeStr += makePart(elem.text)
        typeStr += makePart(elem.tail)

    return convertDTypeConst(typeStr.replace("const *", "const*"))

def mapDName(name):
    if name in dkeywords:
        return name + "_"
    return name


class DGenerator(OutputGenerator):

    class Command:
        def __init__(self, ret, name, params):
            self.returnType = ret
            self.name = name
            self.params = params

    class Param:
        def __init__(self, typeStr, name):
            self.typeStr = typeStr
            self.name = name

    def __init__(self, moduleName, outFile):
        super().__init__()
        self.moduleName = moduleName
        self.outFile = outFile
        self.basicTypes = {
            "uint8_t": "ubyte",
            "uint16_t": "ushort",
            "uint32_t": "uint",
            "uint64_t": "ulong",
            "int8_t": "byte",
            "int16_t": "short",
            "int32_t": "int",
            "int64_t": "long",
        }
        self.cmds = []
        self.globalCmdNames = {
            "vkGetInstanceProcAddr",
            "vkEnumerateInstanceExtensionProperties",
            "vkEnumerateInstanceLayerProperties",
            "vkCreateInstance"
        }
        self.globalCmds = []
        self.instanceCmdNames = set()
        self.instanceCmds = []
        self.deviceCmdNames = set()
        self.deviceCmds = []

    def logMsg(self, level, *args):
        # shut down logging during dev to see debug output
        # super().logMsg(level, *args)
        pass

    def beginFile(self, opts):
        # generator base class open and close a file
        # don't want that here as we may output to stdout
        # not calling super on purpose
        self.sf = SourceFile(self.outFile)
        self.sf.section = Sect.GLOBAL_DEF
        self.sf("/// Vulkan D bindings generated by vkdgen.py for Gfx-d")
        self.sf("module %s;", self.moduleName)
        self.sf()
        self.sf("// Global definitions")
        self.sf()
        self.sf('enum VK_DEFINE_HANDLE(string name) = ')
        with self.sf.indent_block():
            self.sf('"struct "~name~"_handle; alias "~name~" = "~name~"_handle*;";')
        self.sf()
        self.sf("version(X86_64) {")
        with self.sf.indent_block():
            self.sf("enum VK_DEFINE_NON_DISPATCHABLE_HANDLE(string name) = VK_DEFINE_HANDLE!name;")
            self.sf("enum VK_NULL_ND_HANDLE = null;")
        self.sf("} else {")
        with self.sf.indent_block():
            self.sf('enum VK_DEFINE_NON_DISPATCHABLE_HANDLE(string name) = "alias "~name~" = ulong;";')
            self.sf("enum VK_NULL_ND_HANDLE = 0;")
        self.sf("}")

        def initSect(sect, comment):
            self.sf.section = sect
            self.sf()
            self.sf("// %s", comment)
            self.sf()

        initSect(Sect.BASETYPE, "Basic types definition")
        for k in self.basicTypes:
            self.sf("alias %s = %s;", k, self.basicTypes[k])

        initSect(Sect.FUNCPTR, "Fonction pointers")
        self.sf("extern(C) {")
        self.sf.indent()

        initSect(Sect.CONST, "Constants")
        initSect(Sect.HANDLE, "Handles")
        initSect(Sect.ENUM, "Enumerations")
        initSect(Sect.STRUCT, "Structures")
        initSect(Sect.CMD, "Commands")


    def endFile(self):
        # not calling super on purpose (see beginFile comment)
        self.sf.section = Sect.FUNCPTR
        self.sf.unindent()
        self.sf("}")

        self.sf.section = Sect.CMD
        self.sf("extern(C) {")
        with self.sf.indent_block():
            for cmd in self.cmds:
                maxLen = 0
                for p in cmd.params:
                    maxLen = max(maxLen, len(p.typeStr))
                fstLine = "alias PFN_{} = {} function (".format(cmd.name, cmd.returnType)
                if len(cmd.params) == 0:
                    self.sf(fstLine+");")
                    continue
                if len(cmd.params) == 1:
                    self.sf("%s%s %s);", fstLine, cmd.params[0].typeStr, cmd.params[0].name)
                    continue
                lineSpace = fstLine
                for i, p in enumerate(cmd.params):
                    spacer = " " * (maxLen-len(p.typeStr))
                    endLine = ");" if i == len(cmd.params)-1 else ","
                    self.sf("%s%s%s %s%s", lineSpace, p.typeStr, spacer, p.name, endLine)
                    lineSpace = " "*len(fstLine)
        self.sf("}")

        self.sf.writeOut()

    def beginFeature(self, interface, emit):
        super().beginFeature(interface, emit)
        # print("beginFeature", interface.get("name"))
        pass

    def endFeature(self):
        super().endFeature()


    def genType(self, typeinfo, name):
        super().genType(typeinfo, name)
        if "category" not in typeinfo.elem.attrib:
            return
        category = typeinfo.elem.attrib["category"]

        if category == "basetype" or category == "bitmask":
            self.sf.section = Sect.BASETYPE
            self.sf("alias %s = %s;", name, typeinfo.elem.find("type").text)

        elif category == "handle":
            typeStr = typeinfo.elem.find("type").text
            self.sf.section = Sect.HANDLE
            self.sf('mixin(%s!"%s");', typeStr, name)

        elif category == "struct" or category == "union":
            self.genStruct(typeinfo, name)

        elif category == "funcpointer":
            returnType = re.match( re_funcptr, typeinfo.elem.text ).group( 1 )
            params = "".join( islice( typeinfo.elem.itertext(), 2, None ))[ 2: ]
            if params == "void);" or params == " void );" : params = ");"
            #else: params = ' '.join( ' '.join( line.strip() for line in params.splitlines()).split())
            else:
                concatParams = ""
                for line in params.splitlines():
                    lineSplit = line.split()
                    if len( lineSplit ) > 2:
                        concatParams += ' ' + convertTypeConst( lineSplit[ 0 ] + ' ' + lineSplit[ 1 ] ) + ' ' + lineSplit[ 2 ]
                    else:
                        concatParams += ' ' + ' '.join( param for param in lineSplit )

                params = concatParams[ 2: ]

            self.sf.section = Sect.FUNCPTR
            self.sf("alias %s = %s function(%s", name, returnType, params)


    def genEnum(self, enuminfo, name):
        super().genEnum(enuminfo, name)
        (_, strVal) = self.enumToValue(enuminfo.elem, False)
        self.sf.section = Sect.CONST
        self.sf("enum %s = %s;", name,
                strVal.replace("0ULL", "0uL").replace("0U", "0u"))

    def genGroup(self, groupinfo, name):
        super().genGroup(groupinfo, name)
        repStr = ""
        if name.endswith("FlagBits"):
            repStr = " : VkFlags"

        maxLen = 0
        members = []
        for elem in groupinfo.elem.findall("enum"):
            (numVal, strVal) = self.enumToValue(elem, True)
            membName = elem.get("name")
            maxLen = max(maxLen, len(membName))
            members.append([membName, numVal])

        self.sf.section = Sect.ENUM
        self.sf("enum %s%s {", name, repStr)
        with self.sf.indent_block():
            for m in members:
                spacer = " " * (maxLen - len(m[0]))
                self.sf("%s%s = %s,", m[0], spacer, m[1])
        self.sf("}")
        for m in members:
            spacer = " " * (maxLen - len(m[0]))
            self.sf("enum %s%s = %s.%s;", m[0], spacer, name, m[0])
        self.sf()

    def genStruct(self, typeinfo, name):
        super().genStruct(typeinfo, name)
        category = typeinfo.elem.attrib["category"]
        maxLen = 0
        members = []
        for member in typeinfo.elem.findall(".//member"):
            typeStr = makeDParamType(member)
            maxLen = max(maxLen, len(typeStr))
            memName = member.find("name").text
            members.append([typeStr, mapDName(memName)])
        self.sf.section = Sect.STRUCT
        self.sf("%s %s {", category, name)
        with self.sf.indent_block():
            for member in members:
                spacer = " " * (maxLen - len(member[0]) + 1)
                self.sf("%s%s%s;", member[0], spacer, member[1])
        self.sf("}")

    def genCmd(self, cmdinfo, name):
        super().genCmd(cmdinfo, name)
        typeStr = cmdinfo.elem.findall("./proto/type")[0].text
        params=[]
        for pElem in cmdinfo.elem.findall("./param"):
            p = DGenerator.Param(makeDParamType(pElem), pElem.find("name").text)
            params.append(p)

        cmd = DGenerator.Command(typeStr, name, params)

        self.cmds.append(cmd)

        if name in self.globalCmdNames:
            self.globalCmds.append(cmd)
        elif len(params) and params[0].name in { "VkDevice", "VkQueue", "VkCommandBuffer" }:
            self.deviceCmds.append(cmd)
            self.deviceCmdNames.add(name)
        else:
            self.instanceCmds.append(cmd)
            self.instanceCmdNames.add(name)


# main driver starts here

if __name__ == "__main__":

    import sys
    import os
    from os import path
    import argparse

    vkdgenDir = os.path.dirname(os.path.realpath(__file__))
    vkXml = path.join(vkdgenDir, "vk.xml")

    parser = argparse.ArgumentParser(description="Generate Vulkan D bindings")

    parser.add_argument("-m, --module", dest="module", metavar="MODULE",
                help="D module name")
    parser.add_argument("-r, --registry", dest="registry", metavar="REGISTRY",
                help="Path to the XML registry [{}]".format(vkXml), default=vkXml)
    parser.add_argument("-o, --output", dest="output", metavar="OUTPUT",
                help="D output file to generate [stdout].", default="[stdout]")

    args = parser.parse_args(sys.argv[1:])

    outFile = sys.stdout if args.output == "[stdout]" else open(args.output, "w")

    gen = DGenerator(args.module, outFile)
    reg = Registry()
    reg.loadElementTree( etree.parse( args.registry ))
    reg.setGenerator( gen )
    reg.apiGen( GeneratorOptions(
        apiname = "vulkan",
        # addExtensions = ".*",
    ))

    if args.output != "[stdout]":
        outFile.close()
