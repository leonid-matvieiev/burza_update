0<1# :: ^
""" Со след строки bat-код до последнего :: и тройных кавычек
@setlocal enabledelayedexpansion & py -3 -x "%~f0" %*
@(IF !ERRORLEVEL! NEQ 0 echo ERRORLEVEL !ERRORLEVEL! & pause)
@exit /b !ERRORLEVEL! :: Со след строки py-код """

ps_ = '__cached__' not in dir()

from pathlib import Path
import os, sys, time, re
from copy import deepcopy
# from munch import Munch as eD
from addict import Dict as eD

pyc_var = False  # True  #
debug = False  # True  #
yml_form = True
pfp_out = None
specsyms = '?¶'

keys = 'TokenSizeStr', 'DataOffset', 'DataSize', 'BitIndex', 'FracSize'
rep = '|'.join(keys + ('Template', 'TokenValueStr', 'BitName'))
type_contr = 'TRegCombo', 'TRegNumber', 'TRegEdit'  # , 'TRegList'

# ============================================================================
def prinm(*ps, **ds):
    print(*ps, **ds)
    not debug and print(*ps, **ds, file=fstr)

# ============================================================================
def get_obj_templates(fold):
    """ Построение списка параметров переменных """
    global obj_templates, obj_txts

    if pyc_var and Path('obj_templates.pyc').exists():
        prinm('\nИмпорт информации obj_txts и obj_templates')
        exec('from obj_templates import obj_templates', globals())
        exec('from obj_txts import obj_txts', globals())
        return True

    fpnes = sorted((fpne for fpne in fold.glob('*.dfm')
                    if fpne.is_file() and fpne.stat().st_size > 5),
                    key=lambda fpne: fpne.stat().st_size, reverse=True)
    if not fpnes:
        prinm(f'\t? Файлов "*.dfm" нет')
        return False

    obj_txts = {}
    obj_templates = {}
    prinm('\nИзвлечение информации obj_txts и obj_templates из DFM-файлов')
    for fpne in fpnes:

        txt = fpne.read_text('utf8')
        ss = txt.splitlines()

    #    prinm('Поиск блоков с Шаблонами "Template"')
        templates= {}
        params = eD()
        for i, s in enumerate(ss):
            if i == 108:
                a=5
            if m := re.match('^ *(%s) = (.+)$' % rep, s):
                params[m.group(1)] = i, m.start(1), m.start(2), m.group(2)
                continue
#            print(repr(s))
            mo = re.match(r'^(?:\ufeff)? +object (\w+): (\w+)$', s)
            me = re.match(r'^ +end$', s)
            if (mo or me):
                if (tp := params.pop('Template', None)) and 'object' in params \
                        and params.object[-1] in type_contr:
                    tp = tp[-1].strip("'").split('_', 1)[-1]
                    if 'BitIndex' in params:
                        if params.BitIndex[-1] == '-1':
                            del params.BitIndex
                    if tvs := params.pop('TokenValueStr', None):
                        templates.setdefault(tp, {}).setdefault(
                                    tvs[-1].strip("'"), []).append(params)
                    else:
                        templates.setdefault(tp, []
                            ).append(params)
                if mo: params = eD(object=(mo.group(1), mo.group(2)))
        if templates:
            obj_templates[fpne.name] = templates
            obj_txts[fpne.name] = ss, txt

    if obj_templates:
        prinm(f'  Готово, считано непустых DFM-файлов: {len(fpnes)}')
    else:
        prinm(f'  ? obj_templates пустой')
        return False

    if pyc_var:
        save_dicts('obj_templates', obj_templates, ts='pc')
        save_dicts('obj_txts', obj_txts, ts='c')
    if pyc_var or yml_form:
        obj_templates_v = deepcopy(obj_templates)
        for templates in obj_templates_v.values():
            for Tokens in templates.values():
                if isinstance(Tokens, list):
                    Tokens = {'': Tokens}
                for objs in Tokens.values():
                    for i in range(len(objs)):
                        obj = dict(objs.pop())
                        for par, t in obj.items():
                            if par == 'object': obj[par] = '/'.join(t)
                            else: obj[par] = 'стр {0} знач {3}'.format(*t)
                        objs.insert(0, obj)
        save_dicts('obj_templates', obj_templates_v)
    return True

# ============================================================================
def get_inc_dict(fold):
    global inc_dict

    if pyc_var and Path('inc_dict.pyc').exists():
        prinm('\nИмпорт информации inc_dict')
        exec('from inc_dict import inc_dict', globals())
        return True

    fpne_inc = fold.joinpath('designer_MapROM.inc')
    prinm(fpne_inc.name)
    if not fpne_inc.exists():
        prinm(f'\t? Файл в {fold.name} не найден')
        return False

    dt = time.time() - fpne_inc.stat().st_mtime
    if dt > (60 * 15, 60 * 60 * 24 * 10)[0]:
        tdt = list(time.gmtime(dt))
        tdt[:3] = tdt[0] - 1970, tdt[1] - 1, tdt[2] - 1
        for n, s in zip(tdt[:5], 'Года Месяцев Дней Часов Минут'.split()):
            if n: break
        prinm(f'\t? Файлу {s} > {n}, возможно необходимо перегенерить')

    prinm('\nИзвлечение информации inc_dict')
    inc_txt = fpne_inc.read_text('cp1251')
    # Имя устройства из первого блока
    devname = re.search(r'(?m)^;\s*Устройство:\s*(.+?)\s*$', inc_txt).group(1)
    prinm(f'  Устройство: "{devname}"')

    prinm(end='  Создание первичного списка из блоков ... ', flush=True)
    inc_dict = {}
    segs = []  #'UserInfo' UST
    arrs = []  #''
    shifts = []  #-1
    counts = []  #-1
    for blok in inc_txt.split('\n\n')[1:]:
        if not re.match(r';(UserInfo|UST)', blok):  # blok.startswith(';UST'):
            continue  # блок пока не используется
        line0, lines = blok.split('\n', 1)  # первая и остальные строки блока
        name, rem = line0[1:].split(':', 1)  # имя и коментарий блока
        ed = eD({p: int(s, 16) for p, s in re.findall(
                    r'(?m)^ +\.equ MapROM_%s_(\w+) = 0x(\w+)' % name, lines)})
        if len(ed) <= 2:
            if rem.lstrip()[:1] not in specsyms:
                name_tmp = '_'.join(segs)
                tmpl = '\\'.join(''.join(t) for t in zip(segs, arrs))
                inc_dict[tmpl].setdefault('#', {}
                        )[str(ed['bit'])] = name[len(name_tmp) + 1:]
                inc_dict[tmpl].setdefault('@', {}
                        )[name[len(name_tmp) + 1:]] = str(ed.pop('bit'))
            continue
        while True:
            name_tmp = segs and '_'.join(segs) + '_' or ''
            if name.startswith(name_tmp):
                segs.append(name[len(name_tmp):])
                if ed.IXLength > 1:
                    arrs.append('%')
                    shifts.append(ed.OffsetIX)
                    counts.append(ed.IXLength)
                else:
                    arrs.append('')
                    shifts.append(-1)
                    counts.append(-1)
                break
            if not segs: break
            segs.pop()
            arrs.pop()
            shifts.pop()
            counts.pop()

        if rem.lstrip()[:1] in specsyms:
            continue

        if name in ('UserInfo', 'UST'):
            ust_begin_adr = ed.address
            ust_sise = ed.OffsetIX

        elif segs and segs[0] == 'UserInfo':
            if len(segs) > 1 and segs[1] == 'WorcData':
                continue
            elif (ed.get('OffsetIX') == 16 and
                ed.get('i') is None and
                ed.get('f') is None):
                ed.d = '16'
            elif (ed.get('IXLength') == 16 and
                ed.get('OffsetIX') == 1 and
                ed.get('i') == 1 and
                ed.get('f') == 0 and
                segs[-1] == 'C'):
                continue

        elif 'i' in ed:
            ed.d = str(ed.pop('i') + ed.f)
            if ed.f: ed.f = str(ed.f)
            else: del ed.f

        ed.address = str(ed.address - ust_begin_adr)
        del ed.bit
        del ed.OffsetIX
        del ed.IXLength
        ed.pop('Length', None)
#        if len(ed) < 2: continue

        ts = '|'.join('%s=%s' % t for t in zip(segs, shifts) if t[1] >= 0)
        if ts:
            ed.update(ts=f"'{ts}'", tc=str(tuple(x for x in counts if x >= 0)))
        inc_dict['\\'.join(''.join(t) for t in zip(segs, arrs))] = ed

    if inc_dict:
        prinm(f'Готово\n  Начальный адрес 0x{ust_begin_adr:X} == '
                f"{ust_begin_adr} и длинна {ust_sise}")
    else:
        prinm(f'? inc_dict пустой')
        return False

    if pyc_var:
        save_dicts('inc_dict', inc_dict, ts='pc')
    if pyc_var or yml_form:
        inc_dict_v = deepcopy(inc_dict)
        for templates, params in inc_dict_v.items():
            tmp = {}
            for k, v in params.items():
                # if isinstance(v, dict):
                if k == '#':
                    for kd, vd in v.items():
                        tmp.setdefault(k, {})[int(kd)] = vd
                    continue
                if k == '@':
                    for kd, vd in v.items():
                        tmp.setdefault(k, {})[kd] = int(vd)
                    continue
                try:
                    tmp[k] = int(v)
                except ValueError:
                    tmp[k] = v.strip("'")
            inc_dict_v[templates] = tmp
        save_dicts('inc_dict', inc_dict_v)
    return True

# ============================================================================
def variants(ns):
    if not ns:
        return []
    if len(ns) == 1:
        return [(i, ) for i in range(ns[0])]
    out = []
    for i in range(ns[0]):
        for t in variants(ns[1:]):
            out.append((i, ) + t)
    return out

# ============================================================================
def tokens_non_matching():
    prinm('\nПоиск несоответствия Токенов')
    for fpne_name, tp_paramss in obj_templates.items():
        print_fpne = True
        for Template, paramss in tp_paramss.items():
            print_Tmpl = True
            if isinstance(paramss, list):
                continue  # Это если не массивы
            if not isinstance(paramss, dict):
                prinm('? Непредусмотренный тип')
                return False
            # Определяем для шаблона влноженость массивов
            if Template not in inc_dict: continue
            dbs = {'|'.join(map(str, t)) for t in variants(  # должно быть
                                    eval(inc_dict[Template].get('tc', '()')))}
            its = set(paramss)  # есть
            sup = its - dbs
            defic = dbs - its
            if sup or defic:
                print_fpne = print_fpne and prinm(fpne_name)
                print_Tmpl = print_Tmpl and prinm(end=f'  ? {Template}')
            if sup:
                if 2 * len(sup) < len(its):
                    prinm(f'  Лишние Токены {len(sup)} из {len(its)}: '
                            + ', '.join(sorted(sup,
                            key=lambda x: [int(d) for d in x.split('|')])))
                else:
                    prinm(f'  Нужные Токены {len(its & dbs)} из {len(its)}: '
                            + ', '.join(sorted(its & dbs,
                            key=lambda x: [int(d) for d in x.split('|')])))
            if defic:
                if 2 * len(defic) < len(dbs):
                    prinm(f'  Нет Токенов {len(defic)} из {len(dbs)}: '
                            + ', '.join(sorted(defic,
                            key=lambda x: [int(d) for d in x.split('|')])))
                else:
                    prinm(f'  Есть Токенов {len(its & dbs)} из {len(dbs)}: '
                            + ', ''  '.join(sorted(its & dbs,
                            key=lambda x: [int(d) for d in x.split('|')])))
    return True

# ============================================================================
def template_non_matching():
    prinm('\nПоиск несоответствия шаблонов')
    # фильтрация базовой инф
    all_inc = {tmpl for tmpl, ed in inc_dict.items() if 'd' in ed}
    all_templates = {tmpl for tmpls in obj_templates.values()
                          for tmpl in tmpls.keys()}
    all_defic = all_inc - all_templates
    prinm(end=f'Недостающие шаблоны: {len(all_defic)} из {len(all_inc)}')
    if all_defic:
        old = ''
        for tmpl in inc_dict.keys():
            if tmpl not in all_defic:
                continue
            t = tmpl.rsplit('\\', 1)
            if len(t) == 2:
                p, n = t
                if old != p:
                    old = p
                    prinm(end=f'\n  {p}\\')
                prinm(end=f'{n} ')
            else:
                old = ''
                prinm(end=f'\n  {t[0]}')
    all_sup = all_templates - all_inc
    prinm(end=f'\nШаблоны без DataSize: {len(all_sup)} из {len(all_templates)}')
    if all_sup:
        old = ''
        for tmpl in sorted(all_sup):
            t = tmpl.rsplit('\\', 1)
            if len(t) == 2:
                p, n = tmpl.rsplit('\\', 1)
                if old != p:
                    old = p
                    prinm(end=f'\n  {p}\\')
                prinm(end=f'{n} ')
            else:
                old = ''
                prinm(end=f'\n  {t[0]}')
        prinm(end=f'\n  Возможно файлы сооотв разным устройствам')
    prinm()
    return True

# ============================================================================
def repair_txts():

    def print_message(s):
        nonlocal print_Tmpl, print_fpne
        print_fpne = print_fpne and prinm()
        print_Tmpl = print_Tmpl and prinm(f'  {Template}')
        prinm(s)

    def analiz_objs():
        nonlocal print_Tmpl, print_fpne
        # биты или одиночные небиты
        dbBNs = dct.dbBNs
        dbNBs = dct.dbNBs

        if 'BitIndex' in objs[0]:
            # это биты
            tokBONs = {}
            tokNOBs = {}
            for obj in objs:
                O = obj['object'][0]  #.object
                B = obj['BitIndex'][-1]  #.BitIndex
                N = ''
                if 'BitName' in obj:
                    N = obj['BitName'][-1]
                    tokNOBs.setdefault(N, []).append((O, B))
                if isinstance(B, dict) and len(B) == 0:
                    prinm(f"{O}, B = {{}} <-= '-1', {N = }")
                    B = '-1'
                tokBONs.setdefault(B, []).append((O, N))

            # форм и выв инф о повт объектах для одинаковых BitName
            print_dup = True
            for N, OBs in tokNOBs.items():
                if len(OBs) < 2:
                    continue
                print_fpne = print_fpne and prinm()
                print_Tmpl = print_Tmpl and prinm(f'  {Template}')
                print_dup = print_dup and prinm(end='    ? '
                    f'{Token and f"Токен {Token}, "}Обнар повт имён битов')
                prinm(end=f"\n      {N}: {', '.join('.'.join(t) for t in OBs)}")
            not print_dup and prinm()

            # форм и выв инф о повт объектах для одинаковых BitIndex
            print_dup = True
            for B, ONs in tokBONs.items():
                if len(ONs) < 2:
                    continue
                print_fpne = print_fpne and prinm()
                print_Tmpl = print_Tmpl and prinm(f'  {Template}')
                print_dup = print_dup and prinm(end='    ? '
                    f'{Token and f"Токен {Token}, "}Обнар повт номеров битов')
                tmp = [O + (N and f'.{N}' or B in dbBNs and f'/{dbBNs[B]}'
                                                or "/''") for O, N in ONs]
                prinm(end=f"\n      {B}: {', '.join(tmp)}")
            not print_dup and prinm()

            # форм и выв инф о несоотв в битах
            its = set(tokBONs)  # есть
            dbs = set(dbBNs)  # должно быть
            sup = its - dbs
            defic = dbs - its
            if sup or defic:
                print_fpne = print_fpne and prinm()
                print_Tmpl = print_Tmpl and prinm(f'  {Template}')
            if sup:
                if 2 * len(sup) < len(its):
                    prinm(f'    ? {Token and f"Токен {Token}, "}Обнар лишние биты {len(sup)} из {len(its)}: ' + ', '.join(
                        f"""{B}{B in tokBONs and tokBONs[B][-1][-1] and f'.{tokBONs[B][-1][-1]}' or B in dbBNs and f'/{dbBNs[B]}' or "/''"}"""
                        for B in sorted(sup, key=lambda x: [int(d) for d in x.split('|')])))
                else:
                    prinm(f'    ? {Token and f"Токен {Token}, "}Обнар нужные биты {len(its & dbs)} из {len(its)}: ' + ', '.join(
                        f"""{B}{B in tokBONs and tokBONs[B][-1][-1] and f'.{tokBONs[B][-1][-1]}' or B in dbBNs and f'/{dbBNs[B]}' or "/''"}"""
                        for B in sorted(its & dbs, key=lambda x: [int(d) for d in x.split('|')])))
            if defic:
                if 2 * len(defic) < len(dbs):
                    prinm(f'    ? {Token and f"Токен {Token}, "}Обнар нет битов {len(defic)} из {len(dbs)}: ' + ', '.join(
                        f"""{B}{B in tokBONs and tokBONs[B][-1][-1] and f'.{tokBONs[B][-1][-1]}' or B in dbBNs and f'/{dbBNs[B]}' or "/''"}"""
                        for B in sorted(defic, key=lambda x: [int(d) for d in x.split('|')])))
                else:
                    tmp = []
                    prinm(f'    ? {Token and f"Токен {Token}, "}Обнар есть битов {len(its & dbs)} из {len(dbs)}: ' + ', '.join(
                        f"""{B}{B in tokBONs and tokBONs[B][-1][-1] and f'.{tokBONs[B][-1][-1]}' or B in dbBNs and f'/{dbBNs[B]}' or "/''"}"""
                        for B in sorted(its & dbs, key=lambda x: [int(d) for d in x.split('|')])))

        # корректировка строк ТХТ-файлов
        objs_2 = []
        for obj in objs:
            obj_2 = eD()  # object='/'.join(obj.object))
            for key in keys[:-1]:
                if key not in obj:
                    continue
                sn, b1, b2, val_0 = obj[key]
                if key == 'BitIndex':
                    # это бит, должен быть даже если нет BitName
                    if isinstance(dbBNs, tuple) and len(dbBNs) == 0:
                        prinm(f"{obj.object[0]}, dbBitname = () <-= '((()))'")
                        dbBitname = '((()))'
                    else:
                        dbBitname = dbBNs.get(val_0)
                    if 'BitName' in obj:
                        # Имя бита уже определено раньше
                        sn_, b1_, b2_, objBitname = obj.BitName
                        objBitname = objBitname.strip("'")
                        if dbBitNum := dbNBs.get(objBitname):
                            if val_0 != dbBitNum:
                                ss[sn] = ss[sn][:b2] + f"{dbBitNum}"
                                obj_2.BitIndex = (f'стр {sn + 1} бит '
                                    f'{val_0}.%s <- {dbBitNum}' % objBitname)
                        elif objBitname != dbBitname:
                            if dbBitname:
                                ss[sn_] = ss[sn_][:b2_] + f"'{dbBitname}'"
                                obj_2.BitName = (f'стр {sn_ + 1} бит '
                                    f'{val_0}.%s <- {dbBitname}' % objBitname)
                            else:
                                ss[sn_] = ss[sn_][:b2_] + "''"
                                obj_2.BitName = (f'стр {sn_ + 1} бит '
                                    f"{val_0}.%s <- ''" % objBitname)
                    else:
                        # Имя бита ещё не определено
                        if dbBitname:
                            ss_Add.append((sn, b1, dbBitname))
                            obj_2.BitName = f'стр {sn + 1}' \
                                    f" бит {val_0}/'' <- {dbBitname}"
                else:
                    # это не бит
                    val_1 = dct[key]
                    if val_0 != val_1:
                        ss[sn] = ss[sn][:b2] + val_1
                        obj_2[key] = f'стр {sn + 1}' \
                                    f' знач {val_0} <- {val_1}'

            if obj_2:  # len(obj_2) > 1:
                objs_2.append(obj_2)
        if objs_2:
            if Token:
                dict_changes.setdefault(fpne_name, {}
                    ).setdefault(Template, {}
                    )[Token] = objs_2
            else:
                dict_changes.setdefault(fpne_name, {}
                    )[Template] = objs_2

    prinm('\nПоиск замечаний и корректировка DFM-файлов')

    dict_changes = {}
    for fpne_name, templates in obj_templates.items():
        prinm(end=f'{fpne_name:16}', flush=True)
        print_fpne = True
        ss, txt = obj_txts[fpne_name]

        ss_Add = []
        for Template, Tokens in templates.items():
            print_Tmpl = True

            ed = inc_dict.get(Template)
            if ed is None:
                print_message(f'    ? Нет в базе указаного шаблона')
                continue

            dct = eD(DataOffset=ed['address'],  #.address,
                DataSize=ed.get('d', '0'),
                FracSize=ed.get('f', '0'),
                TokenSizeStr=ed.get('ts', ''),
                dbBNs=ed.get('#', ()),
                dbNBs=ed.get('@', ()))

            if isinstance(Tokens, list):
                # Немассив, возможно битовых полей
                Tokens = {'': Tokens}
            elif not isinstance(Tokens, dict):
                print_message(f'    ? Неожиданный тип {type(Tokens)}')
                return False
                # Массив, возможно многомерный, возможно битовых полей

            for Token, objs in Tokens.items():
                if not objs:
                    print_message(f'    ? {Token and f"Token {Token} "}пустой')
                    continue

                # Поиск замечаний к объектам
                if 'BitIndex' not in objs[0] and len(objs) > 1:  # не биты
                    print_message(f'    ? {Token and f"Token {Token}, "}'
                                        'Повт елементов: '
                            f'{" ".join(obj.object[0] for obj in objs)}')

                analiz_objs()

        for sn, b1, val in sorted(ss_Add, reverse=True):
            ss.insert(sn + 1, f"{' ' * b1}BitName = '{val}'")

        txt_out = '\n'.join(ss) + '\n'[:txt.endswith('\n')]
        if txt_out == txt:
            prinm(f'Без изменений')
            continue
        if print_Tmpl and print_fpne:
            prinm(f'Кое что исправлено')
        else:
            prinm(f'    Кое что исправлено')

        pfp_out.joinpath(fpne_name).write_text(txt_out, 'utf8')

    if not dict_changes:
        prinm('! Ни один файл не изменён')
        return
    if yml_form:
        dict_changes_v = deepcopy(dict_changes)
        for templates in dict_changes_v.values():
            for Tokens in templates.values():
                if isinstance(Tokens, list):
                    Tokens = {'': Tokens}
                for objs in Tokens.values():
                    for i in range(len(objs)):
                        objs.insert(0, dict(objs.pop()))
        save_dicts('dict_changes', dict_changes_v)


# ============================================================================
def main():
    global debug, fold, pfp_out

    prinm('Проверка наличия необходимых файлов')
    if len(sys.argv) > 1:
        fold = Path(sys.argv[1])
##    elif debs := list(Path('.').glob('$*/designer_MapROM.inc')):
##        if Path(sys.argv[0]).parent.samefile(
##                r'D:\0d\_OneDrive\W\MLM\Temes2\PC8xn_PR9\py\burza_update'):
##            debug = True
##        fold = debs[0].parent
    else:
        prinm(f'\t? Нет параметров, перетащите папку на скрипт')
        if debug:
#            fold = Path('DFM_0_58')
            fold = Path('DFM_0_58_dbg')
        else:
            return
#            fold = Path('PC83AB3F1')
#            fold = Path('PC83AB3F1_(2)')

    if not fold.exists():
        prinm(f'\t? Путь "{fold.name}" не найден')
        return

    # Определение имени и пересоздание выходной папки
    fp_out = re.sub(r'(_\(\d+\))$', '', str(fold))
    for i in range(2, 10):
        if debug:
            pfp_out = Path(f'{fp_out}_(1)')
            break
        pfp_out = Path(f'{fp_out}_({i})')
        if not pfp_out.exists():
            break
    else:
        tmp_outs = sorted(Path(fold.parent).glob(f'{fp_out}_(*)'),
                                key=lambda x: x.stat().st_mtime)
        if fold in tmp_outs:
            tmp_outs.remove(fold)
        pfp_out = tmp_outs[0]
        os.system(f'rd /q /s {pfp_out} >nul')
        # os.system(f'for /d %a in ("{fp_out}_(*)") do rd /s /q "%a" >nul')
    if pfp_out.exists():
        os.system(f'rd /q /s {pfp_out} >nul')
    pfp_out.mkdir()
    prinm(f'Выходная папка: {pfp_out.name}')
    os.system(fr'copy /y {fold}\designer_MapROM.inc {pfp_out} >nul')
    #     sys.exit('khaFJKHAS')

    if not get_inc_dict(fold):
        return

    if not get_obj_templates(fold):
        return

    if not template_non_matching():
        return

    if not tokens_non_matching():
        return

    repair_txts()

# ============================================================================
def save_dicts(dct_var, dct, ts='y'):
    import yaml
    from py_compile import compile as compile_py
    from pprint import pprint
    # Запись dev_tabless в файл для контроля
    fpn = Path(dct_var)
    fpne_py = fpn.with_suffix('.py')
    if 'p' in ts:  # Запись в большой *_.py файл без компиляции
        prinm(end=f'  Файл {fpne_py.name} ... ', flush=True)
        with fpne_py.open('w', encoding='utf8') as fx:
            dct_var and print(end=f'{dct_var} = ', file=fx, flush=True)
            pprint(dct, stream=fx, width=256, compact=True, sort_dicts=False)
        prinm(end='створено, записано', flush=True)
    if 'c' in ts:  # Запись в *.py файл и компиляция
        if 'p' not in ts:  # Запись в большой *_.py файл без компиляции
            prinm(end=f'  Файл {fpne_py.name} ... ', flush=True)
            with fpne_py.open('w', encoding='utf8') as fx:
                dct_var and print(end=f'{dct_var} = ', file=fx, flush=True)
                print(dct, file=fx)
            prinm(end=f'створено, записано ... ', flush=True)
        compile_py(fpne_py.name, fpne_py.with_suffix('.pyc'))
        prinm(end=', скомпильовано', flush=True)
    if 'c' in ts or 'p' in ts:
        prinm()
    if 'y' in ts:  # Запись в *.yml файл
        fpne_yml = pfp_out / fpn.with_suffix('.yml').name
        prinm(end=f'  Файл {fpne_yml.name} ... ', flush=True)
        with fpne_yml.open('w', encoding='utf8') as fx:  #
            yaml.dump(dct, fx, default_flow_style=False,
                                allow_unicode=True, sort_keys=False)
        prinm('створено, записано')
    if 'c' in ts:
        if 'p' in ts:
            fpne_py_ = fpne_py.with_name("_.".join(fpne_py.name.rsplit('.', 1)))
            fpne_py.replace(fpne_py_)
        else:
            os.system(f'del /Q "{fpne_py.name}" >nul')


# ============================================================================
if __name__ == '__main__':
    if debug:
        main()
    else:
        fne_txt_out = 'out.txt'
        with open(fne_txt_out, 'w', encoding='utf8') as fstr:
            main()
        if pfp_out is not None:
            os.system(f'move /y {fne_txt_out} {pfp_out} >nul')
            os.startfile(str(pfp_out / fne_txt_out))
        else:
            os.system(f'del /q {fne_txt_out} >nul')
    if not ps_: os.system('timeout /t 60')
