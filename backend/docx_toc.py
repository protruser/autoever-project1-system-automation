"""DOCX 목차(TOC) 자동 생성/갱신 유틸리티.

python-docx는 실제 페이지 배치를 계산하지 못해서, docx_builder.add_toc()가
심어둔 TOC 필드(<w:fldSimple>이든 <w:fldChar> 복합 필드든)에 목차 항목·페이지
번호를 채워 넣을 수 없다 - 게다가 그렇게 python-docx로 손으로 만든 필드는
LibreOffice가 자기 내부의 "목차 인덱스" 객체로 인식하지 못해
getDocumentIndexes()로도 갱신이 안 되는 것을 확인했다(both fldSimple/fldChar
시도 모두 getDocumentIndexes().getCount() == 0).

그래서 이 모듈은 필드를 "갱신"하는 대신, 헤드리스 LibreOffice(UNO)로 문서를
열어 docx_builder.TOC_TITLE 문단 바로 다음의 빈 문단 자리에 LibreOffice
네이티브 com.sun.star.text.ContentIndex 객체를 직접 만들어 넣고 update()해서
- 사람이 Word에서 "삽입 > 목차" 했을 때와 같은 결과를 - 다시 docx로 저장한다.
최종 사용자는 열자마자 완성된 목차를 본다.

LibreOffice가 없거나 실행에 실패하면(배포 환경에 미설치, 앵커 문단을 못 찾음
등) 예외를 던지지 않고 원본 바이트를 그대로 돌려준다 - 목차 채우기는 있으면
좋은 마감 처리이지, 이것 때문에 보고서 다운로드 자체가 막히면 안 된다.

주의: pyuno(uno 모듈)는 pip으로 못 깐다 - LibreOffice 배포판이 시스템 python에
같이 설치하는 바이너리 확장(pyuno.so)이라, backend_venv 안에서 `import uno`를
그냥 하면 ModuleNotFoundError가 난다(직접 이 스크립트를 시스템 python3로 돌려서
검증할 땐 안 보이다가, 실제 서버(venv로 uvicorn 실행)에서만 조용히 실패해
목차가 안 채워지는 형태로 나타났었다). _ensure_uno_importable()이 venv와 같은
마이너 버전의 시스템 site-packages 경로를 찾아 sys.path에 얹어서 우회한다 -
venv는 기반 인터프리터(ABI)를 시스템과 공유하므로 이 우회가 유효하다.
"""
import logging
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

log = logging.getLogger(__name__)


def _ensure_uno_importable():
    try:
        import uno  # noqa: F401
        return True
    except ImportError:
        pass
    major, minor = sys.version_info[:2]
    candidates = [
        f"/usr/lib64/python{major}.{minor}/site-packages",
        f"/usr/lib/python{major}.{minor}/site-packages",
        f"/usr/lib/python3/dist-packages",
        f"/usr/lib/libreoffice/program",
        f"/usr/lib64/libreoffice/program",
    ]
    for path in candidates:
        if os.path.isdir(path) and path not in sys.path:
            sys.path.append(path)
    try:
        import uno  # noqa: F401
        return True
    except ImportError:
        log.warning("uno 모듈을 찾지 못했습니다(pyuno 미설치?). 시도 경로: %s", candidates)
        return False


def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _prop(name, value):
    from com.sun.star.beans import PropertyValue
    p = PropertyValue()
    p.Name = name
    p.Value = value
    return p


def _insert_native_toc(doc):
    """docx_builder.TOC_TITLE 문단 바로 다음의 빈 문단 자리에 LibreOffice
    네이티브 목차 인덱스를 만들어 넣고 update()한다. 앵커 문단을 못 찾으면
    (예: docx_builder가 목차 없이 문서를 만든 경우) 조용히 아무것도 안 한다."""
    from docx_builder import TOC_TITLE

    text = doc.getText()
    enum = text.createEnumeration()
    found_title = False
    target = None
    while enum.hasMoreElements():
        el = enum.nextElement()
        if not el.supportsService("com.sun.star.text.Paragraph"):
            continue
        if found_title:
            target = el
            break
        if el.getString().strip() == TOC_TITLE.strip():
            found_title = True
    if target is None:
        log.warning("TOC 앵커 문단을 찾지 못해 목차 삽입을 건너뜁니다.")
        return

    cursor = text.createTextCursorByRange(target.getStart())
    cursor.gotoEndOfParagraph(True)
    toc = doc.createInstance("com.sun.star.text.ContentIndex")
    toc.CreateFromOutline = True
    toc.Level = 2
    toc.Title = ""  # docx_builder가 이미 "목  차" 제목을 넣어뒀으니 중복 방지
    text.insertTextContent(cursor, toc, True)
    toc.update()
    _tighten_toc_style(doc)


def _tighten_toc_style(doc):
    """LibreOffice가 목차 항목에 쓰는 문단 스타일(Contents 1/2, 실제로는 "TOC 1"/
    "TOC 2")은 기본적으로 본문 Normal 스타일의 문단 간격(10pt)을 그대로 물려받아
    항목 사이가 필요 이상으로 벌어진다. 항목별로 직접 손대는 대신 스타일
    자체의 간격을 줄이고 굵게 만들어 모든 레벨에 한 번에 적용한다."""
    try:
        para_styles = doc.StyleFamilies.getByName("ParagraphStyles")
        for name in para_styles.getElementNames():
            if not (name.startswith("Contents") or name.startswith("TOC")):
                continue
            style = para_styles.getByName(name)
            style.ParaTopMargin = 0
            style.ParaBottomMargin = 70  # 1/100mm ≈ 2pt - 붙지는 않으면서 촘촘하게
            style.CharWeight = 150.0  # com.sun.star.awt.FontWeight.BOLD
    except Exception:
        log.exception("목차 스타일 조정 실패 - 기본 간격/굵기로 둡니다.")


def refresh_fields(docx_bytes: bytes, timeout: float = 25.0) -> bytes:
    if not shutil.which("soffice"):
        log.warning("soffice가 없어 DOCX 목차 필드 갱신을 건너뜁니다.")
        return docx_bytes
    if not _ensure_uno_importable():
        return docx_bytes

    work_dir = tempfile.mkdtemp(prefix="docx_toc_")
    profile_dir = os.path.join(work_dir, "lo_profile")
    in_path = os.path.join(work_dir, "in.docx")
    out_path = os.path.join(work_dir, "out.docx")
    port = _free_port()
    proc = None

    try:
        with open(in_path, "wb") as f:
            f.write(docx_bytes)

        proc = subprocess.Popen(
            [
                "soffice", "--headless", "--invisible", "--nocrashreport",
                "--nodefault", "--norestore", "--nolockcheck", "--nologo",
                f"-env:UserInstallation=file://{profile_dir}",
                f"--accept=socket,host=localhost,port={port};urp;",
            ],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

        import uno
        local_ctx = uno.getComponentContext()
        resolver = local_ctx.ServiceManager.createInstanceWithContext(
            "com.sun.star.bridge.UnoUrlResolver", local_ctx
        )

        ctx = None
        deadline = time.time() + timeout
        while time.time() < deadline:
            if proc.poll() is not None:
                raise RuntimeError(f"soffice가 조기 종료됨 (exit={proc.returncode})")
            try:
                ctx = resolver.resolve(
                    f"uno:socket,host=localhost,port={port};urp;StarOffice.ComponentContext"
                )
                break
            except Exception:
                time.sleep(0.3)
        if ctx is None:
            raise TimeoutError("soffice UNO 연결 타임아웃")

        smgr = ctx.ServiceManager
        desktop = smgr.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
        doc = desktop.loadComponentFromURL(
            "file://" + in_path, "_blank", 0, (_prop("Hidden", True),)
        )
        try:
            _insert_native_toc(doc)
            doc.storeToURL(
                "file://" + out_path, (_prop("FilterName", "MS Word 2007 XML"),)
            )
        finally:
            doc.close(False)

        with open(out_path, "rb") as f:
            return f.read()

    except Exception:
        log.exception("DOCX 목차 필드 갱신 실패 - 원본을 그대로 반환합니다.")
        return docx_bytes
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except Exception:
                proc.kill()
        shutil.rmtree(work_dir, ignore_errors=True)
