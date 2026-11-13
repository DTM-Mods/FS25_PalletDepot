"""Prepare scratch copies and a GE-only harness that runs the actual native-cargo loader."""
from pathlib import Path
import json
import posixpath
import shutil
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/native_ge_check_v3'
GAME = Path('G:/SteamLibrary/steamapps/common/Farming Simulator 25')
PROFILE = ROOT.parents[1]


def lua(value):
    if isinstance(value, dict):
        return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    if isinstance(value, str):
        return json.dumps(value)
    return str(value).lower()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'renders').mkdir(exist_ok=True)
    sources = {}
    with zipfile.ZipFile(PROFILE / 'mods/FS25_Fed_Produktions_Pack.zip') as archive:
        lettuce = GAME / 'data/objects/pallets/lettuceBoxPallet/lettuceBoxPallet.xml'
        for ft, name, vehicle_data, model_data, model_path in [
            (5, 'lettuce', lettuce.read_bytes(), lettuce.with_suffix('.i3d').read_bytes(),
             lettuce.with_suffix('.i3d').as_posix()),
            (6, 'carrot_bags', archive.read('Paletten/Palette_Suppe_Karottensack.xml'),
             archive.read('Paletten/models/Palette_Suppe_Karottensack.i3d'),
             'Paletten/models/Palette_Suppe_Karottensack.i3d'),
            (7, 'creamed_spinach', archive.read('Paletten/Palette_Suppe_Rahmspinat.xml'),
             archive.read('Paletten/models/Palette_Suppe_Rahmspinat.i3d'),
             'Paletten/models/Palette_Suppe_Rahmspinat.i3d'),
            (8, 'beet_soup', (GAME / 'data/objects/pallets/soupCansPallet/soupCansPallet.xml').read_bytes(),
             (GAME / 'data/objects/pallets/soupCansPallet/soupCansPallet.i3d').read_bytes(),
             (GAME / 'data/objects/pallets/soupCansPallet/soupCansPallet.i3d').as_posix())
        ]:
            vehicle, model = ET.fromstring(vehicle_data), ET.fromstring(model_data)
            folder = OUT / name
            folder.mkdir(exist_ok=True)
            shapes = model.find('Shapes')
            if ft in (5, 8):
                shapes.set('externalShapesFile', str(Path(model_path).parent / shapes.get('externalShapesFile')).replace('\\', '/'))
            else:
                # Only this non-DLC mod reference is copied into scratch; base-game shapes stay in place.
                shape_name = shapes.get('externalShapesFile')
                (folder / shape_name).write_bytes(archive.read(posixpath.join(posixpath.dirname(model_path), shape_name)))
                for file in model.findall('Files/File'):
                    original = posixpath.normpath(posixpath.join(posixpath.dirname(model_path), file.get('filename')))
                    local = ROOT / 'build/native_product_assets_v1/textures/FS25_Fed_Produktions_Pack' / original.replace('Paletten/', 'Pallets/')
                    file.set('filename', local.as_posix())
            model_file = folder / (name + '.i3d')
            ET.ElementTree(model).write(model_file, encoding='utf-8', xml_declaration=True)
            # Native protected shapes resolve correctly only through their original I3D.
            # Read the game reference in place; never copy/extract its shapes or save it.
            # Keep the unmodified XML STRING. The runtime, not the harness, must resolve it.
            values = {'vehicle.base.filename': vehicle.findtext('base/filename')}
            values.update({'vehicle.base.size#' + k: float(v) for k, v in vehicle.find('base/size').attrib.items()
                           if k in ('width', 'height', 'length')})
            keys = []
            for c, content in enumerate(vehicle.findall('pallet/content')):
                key = f'vehicle.pallet.content({c})'
                objects = []
                for i, obj in enumerate(content.findall('object')):
                    obj_key = f'{key}.object({i})'
                    objects.append(obj_key)
                    for k, v in obj.attrib.items():
                        if k in ('node', 'tensionBeltNode'):
                            values[obj_key + '#' + k] = v
                keys.append({'key': key, 'objects': objects})
            sources[f'/native/product{ft}.xml'] = {'values': values, 'contents': keys,
                'baseDirectory': GAME.as_posix() + '/' if ft in (5, 8) else
                    (PROFILE / 'mods/FS25_Fed_Produktions_Pack').as_posix() + '/',
                'physicalI3D': model_path if ft in (5, 8) else model_file.as_posix(),
                'mappings': {m.get('id'): m.get('node') for m in vehicle.findall('i3dMappings/i3dMapping')}}
    for size in (1000, 2500, 5000):
        source = ROOT / f'vehicles/depotPallet{size}.i3d'
        model = ET.parse(source)
        for file in model.findall('Files/File'):
            file.set('filename', (source.parent / file.get('filename')).resolve().as_posix())
        shapes = model.find('Shapes')
        shape_name = shapes.get('externalShapesFile')
        shutil.copy2(source.parent / shape_name, OUT / shape_name)
        model.write(OUT / source.name, encoding='utf-8', xml_declaration=True)
    (OUT / 'metadata.lua').write_text('NATIVE_CHECK_DATA=' + lua(sources), encoding='utf-8')
    script = HARNESS.replace('__ROOT__', ROOT.as_posix()).replace('__OUT__', OUT.as_posix())
    script = 'local function runNativeFixCheck()\n' + script + '\nend\n' + \
        "local ok,err=xpcall(runNativeFixCheck,debug.traceback)\nif not ok then print('[NATIVE_FIX_ERROR]',err) end\neditorExit(0)\n"
    (OUT / 'run.lua').write_text(script, encoding='utf-8')
    print(OUT / 'run.lua')


HARNESS = r'''
local ROOT, OUT = "__ROOT__", "__OUT__"
for i=getNumOfChildren(getRootNode())-1,0,-1 do
    local n=getChildAt(getRootNode(),i)
    if string.find(getName(n),'depotPallet',1,true) then delete(n) end
end
source(OUT .. '/metadata.lua')
Utils = Utils or {}
Utils.appendedFunction = function(old, new) return function(...) if old then old(...) end new(...) end end
Utils.prependedFunction = function(old, new) return function(...) new(...) if old then old(...) end end end
Utils.getModNameAndBaseDirectory = function(filename) return nil, NATIVE_CHECK_DATA[filename].baseDirectory end
Utils.getFilename = function(filename, baseDirectory)
    if filename:sub(1,6)=='$data/' then return 'G:/SteamLibrary/steamapps/common/Farming Simulator 25/data/'..filename:sub(7) end
    if filename:match('^%a:/') or filename:sub(1,1)=='/' then return filename end
    return baseDirectory..filename
end
Pallet, Vehicle, FillType = {}, {}, {UNKNOWN=0}
Logging = {warning=function(...) print(string.format(...)) end}
PalletDepotPallets = {isOwnPallet=function() return true end,
    findProductionPallet=function() end, findStorePallet=function() end}
g_fillTypeManager = {getFillTypeByIndex=function(_, ft) return {palletFilename='/native/product'..ft..'.xml'} end}
-- Source-file identifiers are not depot carriers.
PalletDepotPallets.isOwnPallet = function(file) return string.find(file, 'depotPallet', 1, true) ~= nil end
I3DUtil = {}
local function index(components, path)
    local root, rest = string.match(path, '^(%d+)>(.*)$')
    local n = components[tonumber(root)+1].node
    for part in string.gmatch(rest, '%d+') do n=getChildAt(n, tonumber(part)) end
    return n
end
I3DUtil.loadI3DMapping=function(xml, _, components, mappings)
    for name, path in pairs(xml.data.mappings) do mappings[name]=index(components,path) end
end
XMLFile={loadIfExists=function(_, name)
    local data=NATIVE_CHECK_DATA[name]
    if data==nil then return nil end
    local xml={data=data}
    function xml:delete() end
    function xml:getValue(key, default, components, mappings)
        local value=self.data.values[key]
        if value==nil then return default end
        if string.match(key, '#node$') or string.match(key, '#tensionBeltNode$') then
            return mappings[value] or index(components,value)
        end
        return value
    end
    function xml:iterator(key)
        local values={}
        if key=='vehicle.pallet.content' then
            for _, content in ipairs(self.data.contents) do table.insert(values,content.key) end
        else
            for _, content in ipairs(self.data.contents) do if key==content.key..'.object' then values=content.objects end end
        end
        local i=0
        return function() i=i+1 if values[i] then return i,values[i] end end
    end
    return xml
end}
g_i3DManager={loadSharedI3DFileAsync=function(_, filename, _, _, callback, target)
    local data=NATIVE_CHECK_DATA[target.filename]
    assert(filename==Utils.getFilename(data.values['vehicle.base.filename'],data.baseDirectory),
        'Runtime did not resolve original model path: '..filename)
    print('[RESOLVED_NATIVE_PATH]',filename)
    local scene, reason=loadI3DFile(data.physicalI3D,false,false,true)
    callback(target,scene,reason)
    return 1
end, releaseSharedI3DFile=function() end}
source(ROOT..'/scripts/PalletDepotGoodsLook.lua')
local function find(n, name)
    if getName(n)==name then return n end
    for i=0,getNumOfChildren(n)-1 do local r=find(getChildAt(n,i),name) if r then return r end end
end
local cases={}
for _, ft in ipairs({5,6,7,8}) do
    for _, size in ipairs({1000,2500,5000}) do
        local scene=loadI3DFile(OUT..'/depotPallet'..size..'.i3d',false,false,true)
        assert(scene~=0,'Carrier failed to load')
        assert(getShapeIsCPUMesh(find(scene,'contentCollision')),'Tension collision must be a CPU mesh')
        link(getRootNode(),scene)
        local count=({[1000]=1,[2500]=3,[5000]=6})[size]
        local objects={}
        for i=1,count do objects[i]={node=find(scene,string.format('goodsLayer%02d',i)),isActive=true} end
        local v={configFileName='depotPallet'..size..'.xml',size={width=1.2,length=0.8,height=0.144+count*0.22},
            spec_pallet={fillUnitIndex=1,contents={{fillUnitIndex=1,objects=objects}}},palletDepotShownLayers=count}
        function v:getFillUnitFillType() return ft end
        PalletDepotGoodsLook.update(v,ft)
        assert(v.palletDepotGoodsFillType==ft,'Native product did not attach')
        local desc=({[5]='lettuce',[6]='carrot_bags',[7]='creamed_spinach',[8]='beet_soup'})[ft]
        print(string.format('[NATIVE_CHECK] %s %d: %d native row graphs, height %.3f',desc,size,#v.palletDepotGoodsNodes,v.size.height))
        cases[#cases+1]={scene=scene,vehicle=v,name=desc..'_'..size}
        setVisibility(scene,false)
    end
end
local cam=createCamera('nativeCheckCamera',math.rad(38),0.01,100)
link(getRootNode(),cam)
setCamera(cam)
setIsOrthographic(cam,true)
setOrthographicHeight(cam,2.0)
setTranslation(cam,1.6,1.9,2.4)
setDirection(cam,1.6,1.25,2.4,0,1,0)
if DebugRendering and DebugRendering.ALBEDO then setDebugRenderingMode(DebugRendering.ALBEDO) end
for _, case in ipairs(cases) do
    setVisibility(case.scene,true)
    renderScreenshot(OUT..'/renders/'..case.name..'.png',900,900,1,'raw_alpha',0,0,0,0,0,3,12,false)
    setVisibility(case.scene,false)
end
setVisibility(cases[3].scene,true)
print('[NATIVE_CHECK_COMPLETE_V3] twelve native-cargo scenes; raw source paths resolved; CPU meshes PASS')
'''

if __name__ == '__main__':
    main()
