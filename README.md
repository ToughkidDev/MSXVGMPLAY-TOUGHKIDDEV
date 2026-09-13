VGMPlay MSX
===========

Grauw의 VGMPlay MSX를 바탕으로, 큰 PCM 블록을 사용하는 VGM/VGZ 파일도 MSX의
적은 메모리로 재생할 수 있도록 개선한 ToughkidDEV 버전입니다.

원본은 재생 전에 PCM 데이터까지 포함한 VGM 전체를 시스템 메모리에 올려야 했습니다.
이 버전에서는 PCM 블록을 지원하는 사운드 카트리지의 메모리로 바로 보내고,
상대적으로 크기가 작은 레지스터 명령과 대기 명령만 MSX의 매퍼 RAM에 남깁니다.
PCM 때문에 메모리가 부족해서 재생하지 못하던 큰 파일들을 다루는 것이 이 프로젝트의
주된 목적입니다.

스트리밍 로딩 방식
------------------

파일은 재생 전에 처음부터 끝까지 한 번 순서대로 읽습니다. 이 과정에서 PCM과
재생 명령을 분리합니다.

1. VGM 헤더를 읽고, 사용할 사운드칩과 드라이버를 준비합니다.
2. VGM은 MSX-DOS에서 직접 읽고, VGZ는 작은 버퍼 단위로 압축을 풀면서 읽습니다.
   압축을 푼 파일 전체를 RAM에 올리지는 않습니다.
3. 카트리지 메모리로 보낼 수 있는 PCM 블록은 읽는 즉시 해당 장치로 전송합니다.
4. 레지스터 명령, 대기 명령, 종료 명령과 직접 전송 대상이 아닌 데이터 블록은
   매퍼 RAM의 재생용 버퍼에 모읍니다.
5. PCM을 분리하면서 달라진 위치에 맞춰 루프 주소를 보정합니다. 로딩이 끝난 뒤에는
   메모리에서만 명령을 읽어 재생하므로, 재생 중 디스크 접근이 타이밍에 영향을 주지 않습니다.

해당 장치가 연결되어 있으면 다음 PCM/ROM 데이터 블록을 카트리지 메모리로 직접 전송합니다.

| VGM 블록 형식 | 전송 대상 | 대표적인 MSX 장치 |
| --- | --- | --- |
| `0x81` | YM2608 ADPCM | Makoto / OPNA 지원 구성 |
| `0x82` | YM2610 PCM-A | Neotron |
| `0x83` | YM2610 PCM-B | Neotron |
| `0x84` | YMF278B OPL4 ROM | DalSoRi R2 / 호환 OPL4 장치 |
| `0x87` | YMF278B OPL4 RAM | DalSoRi R2 / 호환 OPL4 장치 |
| `0x88` | Y8950 ADPCM | MSX-AUDIO |

물론 시스템 RAM이 전혀 필요 없어진 것은 아닙니다. 레지스터 명령과 대기 명령은
여전히 매퍼 RAM에 보관하므로, 명령 자체가 아주 많은 곡은 메모리가 부족할 수 있습니다.
다만 PCM을 카트리지 메모리로 옮길 수 있는 경우에는 PCM의 크기만큼 시스템 RAM을
확보할 필요가 없습니다.

로딩 중에는 PCM 전송 대상과 진행 상태를 표시합니다. 로딩이 끝나면 곡 정보와 함께
VGM의 사운드칩이 어떤 MSX 드라이버로 재생되는지 보여준 뒤 연주를 시작합니다.

VGZ 처리 방식
-------------

VGZ는 파일을 되돌아가지 않고 앞에서부터 압축을 풀어 처리합니다. 압축 해제에 필요한
32KB 이력 버퍼는 전용 16KB 매퍼 세그먼트 두 개를 임시로 연결해 사용합니다.
이력은 다음 압축 해제 작업에서도 유지하고, 한 단위의 처리가 끝날 때마다 로더와
명령 버퍼가 사용하던 메모리 페이지를 원래대로 복원합니다.

이렇게 하면 전체 파일을 펼쳐 놓지 않고도 압축을 풀면서 재생용 명령 버퍼를 만들 수 있습니다.
임시 세그먼트는 프로그램이 종료될 때 MSX-DOS에서 해제합니다.

Copyright 2015 Laurens Holst

원본 개발을 지원해 주신 l_oliveira, popolon(fr), Pencioner, Supersoniqs,
JunSoft에게 감사드립니다.

프로젝트 정보
-------------

VGMPlay는 MSX에서 여러 사운드칩용 VGM 음악을 재생하는 프로그램입니다.
아래는 원본 VGMPlay MSX의 개발자와 관련 링크입니다.

  * 원작자: Laurens Holst (Grauw) <laurens@grauw.nl>
  * 웹사이트: <http://www.grauw.nl/projects/vgmplay-msx/>
  * 원본 소스: <https://hg.sr.ht/~grauw/vgmplay-msx>
  * 원본 이슈 트래커: <https://todo.sr.ht/~grauw/vgmplay-msx>
  * 관련 포럼: <http://www.msx.org/forum/msx-talk/software/vgmplay-msx>
  * 라이선스: Simplified BSD License

내장 PSG부터 MoonSound, Yamaha SFG까지 다양한 MSX 사운드 확장 장치를 이용합니다.
재생할 수 있는 사운드칩과 장치 구성은 아래 목록을 참고해 주세요.

VGM과 압축 형식인 VGZ를 모두 지원합니다. VGZ는 디스크 공간을 적게 차지하는 대신
압축 해제 때문에 로딩 시간이 더 걸립니다. 필요하면
[MSX용 gunzip](http://www.grauw.nl/projects/gunzip/)이나 PC에서 미리 압축을 풀어
VGM으로 사용할 수도 있습니다.

재생 타이밍의 해상도는 TMS9918 VDP를 사용하는 MSX1에서 50/60Hz,
V9938 또는 V9958 VDP를 사용하는 기종에서 300Hz입니다. MoonSound나 OPL3가 있으면
1130Hz, MSX turboR에서는 4000Hz를 사용합니다.

VGM 음악은 다음 사이트에서 찾아볼 수 있습니다.

  * <http://vgmrips.net/>
  * <http://www.smspower.org/Music/VGMs>
  * <http://opl.wafflenet.com/>


실행 환경
---------

  * MSX, MSX2, MSX2+ 또는 MSX turboR
  * 메인 RAM 128KB
  * 비디오 RAM 16KB
  * MSX-DOS 2


지원 사운드칩
-------------

  * AY-3-8910 PSG / YM2149 SSG x2

    * 내장 PSG, Darky, MegaFlashROM SCC+
  * YM2151 OPM x2

    * Yamaha SFG
  * YM2413 OPLL

    * MSX-MUSIC, FM-PAC
  * YM3526 OPL x2

    * MSX-AUDIO, Music Module, MoonSound, OPL3
  * YM3812 OPL2 x2

    * MoonSound, OPL3
  * YMF262 OPL3 x2

    * MoonSound, OPL3
  * YMF278B OPL4

    * MoonSound, DalSoRi R2 (4MB 모드)
  * Y8950 MSX-AUDIO x2

    * MSX-AUDIO, Music Module, MoonSound (ADPCM 미지원), OPL3 (ADPCM 미지원)
  * K051649 Konami SCC

    * Konami SCC, Konami Sound Cartridge
  * K052539 Konami SCC+

    * Konami Sound Cartridge
  * SN76489 DCSG x2

    * Musical Memory Mapper, Playsoniq, Franky, PSG
  * YM2203 OPN x2

    * Makoto, Neotron, Yamaha SFG + PSG
  * YM2608 OPNA

    * Makoto, Yamaha SFG + PSG + MSX-AUDIO (드럼 미지원)
  * YM2610 OPNB

    * Neotron
  * YM2610B OPNB-B

    * Neotron + Makoto
  * YM2612 OPN2 x2

    * Makoto + turboR PCM, Yamaha SFG + turboR PCM
  * SAA1099

    * SoundStar


사용법
------

MSX-DOS 2에서 재생할 파일 이름을 지정해 실행하면 됩니다.

    vgmplay [옵션] <파일.vgm>

압축된 `.vgz` 파일도 같은 방법으로 실행할 수 있습니다.

옵션은 다음과 같습니다.

  * `/l` — 반복 횟수 지정. 기본값은 2입니다.

    루프가 있는 VGM은 곡 끝에 도달하면 지정된 위치로 돌아가 반복합니다.
    `/L15`처럼 횟수를 지정할 수 있고, `/L` 또는 `/L0`을 쓰면 계속 반복합니다.
    루프가 없는 곡에는 이 옵션이 적용되지 않습니다.

  * `/b` — 재생 중 화면을 검게 전환합니다.

    VDP의 간섭으로 오디오 출력에 잡음이 생기는 기종에서는 이 옵션으로
    잡음이 줄어들 수 있습니다.

Multi Mente에서 VGM 파일을 바로 실행하려면 `MMRET.DAT`에 다음 내용을 추가해 주세요.

    .VGM    VGMPLAY $T
    .VGZ    VGMPLAY $T


개발 및 빌드
------------

VGMPlay는 자유롭게 사용하고 수정할 수 있는 오픈소스 소프트웨어입니다.
버그 제보나 개선 제안, 코드 기여도 환영합니다. 원본 프로젝트와 관련된 문의는
위 프로젝트 정보의 링크를 이용해 주세요.

라이선스 조건을 지키는 범위에서 다른 프로젝트에 코드를 가져다 사용해도 됩니다.

이 저장소에는 빌드에 필요한 Neonlib과 Gunzip 소스가 포함되어 있습니다.
따라서 Git으로 복제한 뒤 Mercurial 하위 저장소를 따로 설정하지 않아도 빌드할 수 있습니다.

macOS와 Linux에서는 프로젝트 디렉토리에서 다음 명령을 실행하면 됩니다.

    make

실행 파일은 `bin/vgmplay.com`, 심볼 파일은 `gen/vgmplay.sym`으로 생성됩니다.

Windows에서는 `Makefile`의 `all` 항목을 참고해 출력 디렉토리를 만든 다음,
Java 빌드 명령을 명령 프롬프트에서 실행하면 됩니다.

빌드 후 openMSX에서 실행하려면 `bin` 디렉토리에 `MSXDOS2.SYS`, `COMMAND2.COM`과
재생할 VGM 파일을 준비하고 `make run`을 실행합니다.

프로젝트에 포함된 [Glass](http://www.grauw.nl/projects/glass/) 어셈블러는
[Java 8](http://java.com/getjava)이 필요합니다.
설치된 Java 버전은 `java -version`으로 확인할 수 있습니다.
