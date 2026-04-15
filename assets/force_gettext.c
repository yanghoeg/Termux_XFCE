#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

/* ------------ logging ------------ */
static int want_log(void){ const char* v=getenv("FORCE_LOG"); return v && strcmp(v,"1")==0; }
static void LOG2(const char* tag, const char* a, const char* b, const char* c){
  if(!want_log()) return;
  const char* p=getenv("FORCE_LOG_PATH");
  if(!p||!*p) p="/data/data/com.termux/files/usr/var/tmp/force_gettext.log";
  FILE* f=fopen(p,"a"); if(!f) return;
  fprintf(f,"[%s] %s | %s | %s\n", tag, a?a:"", b?b:"", c?c:"");
  fclose(f);
}

/* ------------ normalize ------------ */
static unsigned char u8(const char* p,int i){ return (unsigned char)p[i]; }
static const char* ctx_tail(const char* s){ const char* d=strchr(s? s:"", '\004'); return d? d+1 : (s? s:""); }
static void normalize_into(const char* in_raw, char* out, size_t cap, int to_lower){
  const char* in = ctx_tail(in_raw); if(!in){ out[0]='\0'; return; }
  size_t o=0; int tag=0, ws=0;
  for(const char* p=in; *p; ){
    unsigned char c=*p;
    if(c=='<'){ tag=1; p++; continue; }
    if(tag){ if(c=='>') tag=0; p++; continue; }
    if(c=='\n'||c=='\r'||c=='\t'||c==' '){ ws=1; p++; continue; }
    if(c=='_'){ p++; continue; }
    if(c==0xE2 && u8(p,1)==0x80 && (u8(p,2)==0x98 || u8(p,2)==0x99)){ c='\''; p+=3; }
    else if(c==0xE2 && u8(p,1)==0x80 && (u8(p,2)==0x9C || u8(p,2)==0x9D)){ c='"';  p+=3; }
    else if(c==0xE2 && u8(p,1)==0x80 && (u8(p,2)==0x93 || u8(p,2)==0x94)){ c='-';  p+=3; }
    if(ws){ if(o+1<cap) out[o++]=' '; ws=0; }
    if(to_lower && c>='A'&&c<='Z') c=(char)(c-'A'+'a');
    if(o+1<cap) out[o++]=c; p++;
  }
  if(ws && o+1<cap) out[o++]=' ';
  out[o]='\0'; while(o>0 && out[o-1]==' ') out[--o]='\0';
  size_t a=0; while(out[a]==' ') a++; if(a) memmove(out, out+a, o-a+1);
}
static void normalize_key(const char* in, char* out, size_t cap){ normalize_into(in,out,cap,1); }

/* ===== fwd decls ===== */
static const char* try_all(const char* dom, const char* msgid);
static const char* hard_override_core(const char* raw);
void gtk_message_dialog_set_markup(void* dlg, const char* str);

/* ------------ allowlist ------------ */
static int override_allowed_for(const char* domain){
  const char* allow=getenv("FORCE_OVR_ALLOW");
  if(!allow||!*allow)
    allow="messages gtk30 glib20 libxfce4ui-2 xfce4-about mousepad xfdesktop thunar thunarx exo exo-2 garcon xfce4-terminal catfish";
  if(domain){
    if(strncmp(domain,"gimp",4)==0) return 0;
    if(strncmp(domain,"inkscape",8)==0) return 0;
    if(strcmp(domain,"messages")==0) return 1;
  }
  if(!domain||!*domain) return 1;
  size_t n=strlen(domain); const char* p=allow;
  while(*p){ while(*p==' ') p++; const char* s=p; while(*p&&*p!=' ') p++; size_t m=(size_t)(p-s);
    if(m==n && strncmp(s,domain,n)==0) return 1; }
  return 0;
}

/* ------------ hard overrides ------------ */
typedef struct { const char* k; const char* v; } KV;
static const KV EXACT[]={
  {"File","파일"},{"_File","파일(_F)"},{"Edit","편집"},{"_Edit","편집(_E)"},
  {"View","보기"},{"_View","보기(_V)"},{"Go","이동"},{"_Go","이동(_G)"},
  {"Bookmarks","북마크"},{"_Bookmarks","북마크(_B)"},
  {"Help","도움말"},{"_Help","도움말(_H)"},
  {"_Save","저장(_S)"},{"Save","저장"},{"Don't Save","저장 안 함"},{"Don’t Save","저장 안 함"},
  {"_Cancel","취소"},{"Cancel","취소"},
  {"Save Changes","변경 사항 저장"},

  /* Mousepad 헤드라인: 굵게+큰 글씨 */
  {"Do you want to save the changes before closing?",
   "<span weight='bold' size='larger'>닫기 전에 변경 사항을 저장하시겠습니까?</span>"},
  {"If you don't save the document, all the changes will be lost.","문서를 저장하지 않으면 모든 변경 사항이 사라집니다."},

  {"Stock label|_Save","저장(_S)"},{"Stock label|Save","저장"},
  {"Stock label|Don't Save","저장 안 함"},{"Stock label|Don’t Save","저장 안 함"},
  {"Stock label|_Cancel","취소"},{"Stock label|Cancel","취소"},
  {"Stock label|Save Changes","변경 사항 저장"},

  /* 세션 복구 */
  {"It seems that the previous session did not end normally. Do you want to restore the available data?","이전 세션이 정상적으로 종료되지 않은 것 같습니다. 사용 가능한 데이터를 복구하시겠습니까?"},
  {"If not, all this data will be lost.","복구하지 않으면 이 데이터는 모두 손실됩니다."},
  {"It seems that the previous session did not end normally. Do you want to restore the available data? If not, all this data will be lost.","이전 세션이 정상적으로 종료되지 않은 것 같습니다. 사용 가능한 데이터를 복구하시겠습니까? 복구하지 않으면 이 데이터는 모두 손실됩니다."},

  /* 바탕화면 우클릭 3종 */
  {"Open Terminal Here","여기서 터미널 열기"},{"_Open Terminal Here","여기서 터미널 열기"},
  {"Find in this folder","이 폴더에서 찾기"},{"Find in This Folder","이 폴더에서 찾기"},
  {"Search in this folder","이 폴더에서 검색"},
  {"Scripts","스크립트"},

  /* 런처 라벨 */
  {"Attention","주의"},
  {"Untrusted application launcher","신뢰할 수 없는 프로그램 실행 아이콘"},
  {"Launch Anyway","어쨌든 실행"},{"_Launch Anyway","어쨌든 실행(_L)"},
  {"Mark As Secure And Launch","신뢰로 표시하고 실행"},{"_Mark As Secure And Launch","신뢰로 표시하고 실행(_M)"},

  /* Timeout 직일치 */
  {"Timeout was reached","시간 제한에 도달했습니다"},
  {"Operation timed out","시간 제한에 도달했습니다"},
  {"Timed out","시간 제한에 도달했습니다"},
  {"The connection timed out","시간 제한에 도달했습니다"},

  /* ===== xfce4-about ===== */
  /* 창 제목 */
  {"About the Xfce Desktop Environment","Xfce 데스크톱 환경 정보"},
  /* 탭 */
  {"System","시스템"},
  {"Information","정보"},{"Info","정보"},{"About","정보"},
  {"Credits","만든 사람"},{"Contributors","만든 사람"},
  {"Copyright","저작권"},
  /* 버튼 */
  {"_Close","닫기(_C)"},{"Close","닫기"},{"_Help","도움말(_H)"},
  /* 라벨(좌측 컬럼) */
  {"Device","장치"},
  {"OS Name","운영 체제명"},
  {"OS Type","운영 체제 형식"},
  {"Distributor","제공자"},
  {"Xfce Version","Xfce 버전"},
  {"GTK Version","GTK 버전"},
  {"Kernel Version","커널 버전"},
  {"Windowing System","창 관리 시스템"},
  {"Memory","메모리"},
};

typedef struct { const char* needle; const char* trans; } SUB;
static const SUB SUBSTR[]={
  {"It seems that the previous session did not end normally. Do you want to restore the available data?","이전 세션이 정상적으로 종료되지 않은 것 같습니다. 사용 가능한 데이터를 복구하시겠습니까?"},
  {"If not, all this data will be lost.","복구하지 않으면 이 데이터는 모두 손실됩니다."},
  {"Do you want to save the changes before closing?","<span weight='bold' size='larger'>닫기 전에 변경 사항을 저장하시겠습니까?</span>"},
  {"If you don't save the document, all the changes will be lost.","문서를 저장하지 않으면 모든 변경 사항이 사라집니다."},
  {"Open Terminal Here","여기서 터미널 열기"},
  {"Find in this folder","이 폴더에서 찾기"},
  {"Search in this folder","이 폴더에서 검색"},
  {"Scripts","스크립트"},
};

/* ===== Launcher: 정확히 2줄 + 빈 줄 ===== */
static __thread int TLS_IS_LAUNCHER = 0;
static const char* dyn_launcher_detail(const char* raw){
  if(!raw) return NULL;
  if(strstr(raw,"The desktop file") || strstr(raw,"desktop file")){
    static char buf[256];
    snprintf(buf,sizeof(buf),
      "이 실행 아이콘은 안전하지 않은 위치에 있거나 신뢰/실행 가능한 파일로 표시되어 있지 않습니다. 이 프로그램을 신뢰하지 않으면 취소를 누르세요.\n\n");
    TLS_IS_LAUNCHER = 1;
    return buf;
  }
  return NULL;
}

/* 핵심 오버라이드 */
static const char* hard_override_core(const char* raw){
  if(!raw) return NULL;

  /* 런처 본문(2줄 고정) */
  const char* d = dyn_launcher_detail(raw); if(d) return d;

  /* Timeout 계열 느슨 매칭 */
  char pr[256]; normalize_key(raw, pr, sizeof(pr));
  if(strstr(pr,"timeout was reached") || strstr(pr,"operation timed out") ||
     strstr(pr,"timed out") || strstr(pr,"connection timed out"))
    return "시간 제한에 도달했습니다";

  /* EXACT 완전일치 */
  char body[1024]; normalize_key(raw, body, sizeof(body));
  for(size_t i=0;i<sizeof(EXACT)/sizeof(EXACT[0]); ++i){
    char keyn[1024]; normalize_key(EXACT[i].k, keyn, sizeof(keyn));
    if(strcmp(body,keyn)==0) return EXACT[i].v;
  }
  /* SUBSTR 부분일치 */
  for(size_t i=0;i<sizeof(SUBSTR)/sizeof(SUBSTR[0]); ++i){
    char needn[1024]; normalize_key(SUBSTR[i].needle, needn, sizeof(needn));
    if(strstr(body,needn)) return SUBSTR[i].trans;
  }
  return NULL;
}

/* ------------ .mo loader/cache ------------ */
typedef struct Entry{ char* key; char* val; struct Entry* next; } Entry;
typedef struct Dict{ Entry** b; size_t n; } Dict;
static uint32_t djb2(const char*s){ uint32_t h=5381; int c; while((c=*s++)) h=((h<<5)+h)+c; return h; }
static Dict* dict_new(size_t n){ Dict* d=calloc(1,sizeof(Dict)); d->n=n?n:1024; d->b=calloc(d->n,sizeof(Entry*)); return d; }
static void dict_put(Dict* d,const char*k,const char*v){ if(!d||!k||!v) return; uint32_t h=djb2(k)%d->n; Entry* e=malloc(sizeof(*e)); e->key=strdup(k); e->val=strdup(v); e->next=d->b[h]; d->b[h]=e; }
static const char* dict_get(Dict* d,const char*k){ if(!d||!k) return NULL; uint32_t h=djb2(k)%d->n; for(Entry* e=d->b[h]; e; e=e->next) if(strcmp(e->key,k)==0) return e->val; return NULL; }

typedef struct { uint32_t magic,rev,n,offo,offt,hsz,hoff; } H;
static uint32_t sw(uint32_t x){ return (x>>24)|((x>>8)&0xFF00)|((x<<8)&0xFF0000)|(x<<24); }
typedef struct { Dict* d; char* blob; size_t len; int be; } Cat;
static int rf(const char* p,char**o,size_t*L){
  FILE* f=fopen(p,"rb"); if(!f) return -1; fseek(f,0,2); long n=ftell(f);
  if(n<=0||n>50*1024*1024){ fclose(f); return -1; }
  fseek(f,0,0); char* b=malloc((size_t)n); if(!b){ fclose(f); return -1; }
  if(fread(b,1,(size_t)n,f)!=(size_t)n){ fclose(f); free(b); return -1; }
  fclose(f); *o=b; *L=(size_t)n; return 0;
}
static uint32_t rd32(const char*p,int be){ uint32_t v=*(const uint32_t*)p; return be?sw(v):v; }
static Cat* loadmo(const char* path){
  char* b=NULL; size_t L=0; if(rf(path,&b,&L)!=0) return NULL;
  if(L<28){ free(b); return NULL; }
  H* h=(H*)b; int be=0;
  if(h->magic==0x950412de) be=0; else if(h->magic==0xde120495) be=1; else { free(b); return NULL; }
  uint32_t n=rd32((char*)&h->n,be), oo=rd32((char*)&h->offo,be), ot=rd32((char*)&h->offt,be);
  if(n>1000000||oo>L||ot>L||oo+8ULL*n>L||ot+8ULL*n>L){ free(b); return NULL; }
  Dict* d=dict_new(n*2+1);
  for(uint32_t i=0;i<n;i++){
    uint32_t olen=rd32(b+oo+i*8+0,be), ooff=rd32(b+oo+i*8+4,be);
    uint32_t tlen=rd32(b+ot+i*8+0,be), toff=rd32(b+ot+i*8+4,be);
    if(ooff>L||toff>L||ooff+olen>=L||toff+tlen>=L) continue;
    dict_put(d, b+ooff, b+toff);
  }
  Cat* c=calloc(1,sizeof(Cat)); c->d=d; c->blob=b; c->len=L; c->be=be; return c;
}

/* ------------ domain helpers ------------ */
typedef struct Dom{ char* name; Cat* c; struct Dom* next; } Dom;
static Dom* g=NULL; static pthread_mutex_t g_lock=PTHREAD_MUTEX_INITIALIZER;
static const char* envd(const char* k,const char* def){ const char* v=getenv(k); return (v&&*v)?v:def; }
static Cat* loaddom_locked(const char* dom){
  for(Dom* d=g; d; d=d->next) if(strcmp(d->name,dom)==0) return d->c;
  const char* root=envd("FORCE_TEXTDOMAINDIR", envd("TEXTDOMAINDIR","/data/data/com.termux/files/usr/share/locale"));
  const char* lang=envd("FORCE_LANGUAGE","ko");
  const char* langs[3]={0}; if(lang && strchr(lang,'_')){ langs[0]=lang; langs[1]="ko"; } else { langs[0]=lang?lang:"ko"; }
  char path[512]; Cat* c=NULL;
  for(int i=0; langs[i]; i++){ snprintf(path,sizeof(path),"%s/%s/LC_MESSAGES/%s.mo", root, langs[i], dom); c=loadmo(path); if(c) break; }
  Dom* nd=calloc(1,sizeof(Dom)); nd->name=strdup(dom); nd->c=c; nd->next=g; g=nd; return c;
}
static Cat* loaddom(const char* dom){ if(!dom||!*dom) return NULL; pthread_mutex_lock(&g_lock); Cat* c=loaddom_locked(dom); pthread_mutex_unlock(&g_lock); return c; }

static const char* dom_of(const char* d){ if(d&&*d) return d; const char* td=getenv("TEXTDOMAIN"); return (td&&*td)?td:"messages"; }
static const char* lookup(const char* dom,const char* key){ if(!dom||!key) return NULL; Cat* c=loaddom(dom); return c?dict_get(c->d,key):NULL; }
static const char* fallback(const char* key){
  const char* list=getenv("FALLBACK_DOMAINS"); if(!list||!key||!*key) return NULL;
  const char* p=list; while(*p){
    while(*p==' ') p++; const char* s=p; while(*p && *p!=' ') p++;
    size_t n=(size_t)(p-s); if(!n) break; char dom[128];
    if(n>=sizeof(dom)) n=sizeof(dom)-1; memcpy(dom,s,n); dom[n]='\0';
    const char* t=lookup(dom,key); if(t) return t;
  } return NULL;
}
static char* join_ctx(const char* ctx,const char* msg){
  size_t a=strlen(ctx?ctx:""), b=strlen(msg); char* k=malloc(a+1+b+1); if(!k) return NULL;
  memcpy(k,ctx?ctx:"",a); k[a]='\004'; memcpy(k+a+1,msg,b+1); return k;
}
static const char* const CTXS[]={
  "Menu","Action","Stock label","Stock item",
  "ThunarActions","ThunarStandardView","ThunarLauncher",
  "ThunarxMenuProvider","ThunarxAction","Question","Dialog","Message","Title", NULL
};

/* ------------ lookup core ------------ */
static const char* try_all(const char* dom,const char* msgid){
  if(override_allowed_for(dom)){ const char* hv=hard_override_core(msgid); if(hv) return hv; }
  const char* t=lookup(dom,msgid); if(t) return t;

  const char* d=strchr(msgid,'\004');
  if(d){ const char* m=d+1; if(!t) t=lookup(dom,m); if(!t && m[0]=='_') t=lookup(dom,m+1); }
  else if(!t && msgid[0]=='_') t=lookup(dom,msgid+1);
  if(t) return t;

  for(const char* const* C=CTXS; *C; ++C){
    char* k=join_ctx(*C, d? (d+1):msgid); if(!k) continue;
    t=lookup(dom,k); free(k); if(t) return t;
  }

  if(!t) t=fallback(msgid);
  if(!t && d){ const char* m=d+1; t=fallback(m); if(!t && m[0]=='_') t=fallback(m+1); }
  else if(!t && msgid[0]=='_') t=fallback(msgid+1);
  return t;
}

/* ------------ GTK size helper (launcher 전용) ------------ */
static void widen_if_launcher(void *dlg){
  if(!TLS_IS_LAUNCHER || !dlg) return;
  TLS_IS_LAUNCHER = 0;
  static void (*p_gtk_window_set_default_size)(void*,int,int) = NULL;
  static void (*p_gtk_widget_set_size_request)(void*,int,int) = NULL;
  if(!p_gtk_window_set_default_size)
    p_gtk_window_set_default_size = (void(*)(void*,int,int)) dlsym(RTLD_NEXT, "gtk_window_set_default_size");
  if(!p_gtk_widget_set_size_request)
    p_gtk_widget_set_size_request = (void(*)(void*,int,int)) dlsym(RTLD_NEXT, "gtk_widget_set_size_request");
  if(p_gtk_widget_set_size_request) p_gtk_widget_set_size_request(dlg, 680, -1);
  if(p_gtk_window_set_default_size) p_gtk_window_set_default_size(dlg, 680, -1);
}

/* ------------ real symbols ------------ */
static const char* (*rgd)(const char*,const char*)=NULL;
static const char* (*rgdc)(const char*,const char*,int)=NULL;
static const char* (*rgdp2)(const char*,const char*,const char*)=NULL;
static const char* (*r_gettext)(const char*)=NULL;
static const char* (*r_dgettext)(const char*,const char*)=NULL;
static const char* (*r_dcgettext)(const char*,const char*,int)=NULL;
static const char* (*r_ngettext)(const char*,const char*,unsigned long)=NULL;
static const char* (*r_dngettext)(const char*,const char*,const char*,unsigned long)=NULL;
static const char* (*r_dcngettext)(const char*,const char*,const char*,unsigned long,int)=NULL;

/* GTK message dialog constructors */
static void* (*real_gtk_message_dialog_new)(void*,int,int,int,const char*,...)=NULL;
static void* (*real_gtk_message_dialog_new_with_markup)(void*,int,int,int,const char*,...)=NULL;

static void ensure_syms(void){
  if(!rgd)   rgd   = dlsym(RTLD_NEXT,"g_dgettext");
  if(!rgdc)  rgdc  = dlsym(RTLD_NEXT,"g_dcgettext");
  if(!rgdp2) rgdp2 = dlsym(RTLD_NEXT,"g_dpgettext2");
  if(!r_gettext)    r_gettext    = dlsym(RTLD_NEXT,"gettext");
  if(!r_dgettext)   r_dgettext   = dlsym(RTLD_NEXT,"dgettext");
  if(!r_dcgettext)  r_dcgettext  = dlsym(RTLD_NEXT,"dcgettext");
  if(!r_ngettext)   r_ngettext   = dlsym(RTLD_NEXT,"ngettext");
  if(!r_dngettext)  r_dngettext  = dlsym(RTLD_NEXT,"dngettext");
  if(!r_dcngettext) r_dcngettext = dlsym(RTLD_NEXT,"dcngettext");
  if(!real_gtk_message_dialog_new)
    real_gtk_message_dialog_new=(void*(*)(void*,int,int,int,const char*,...))dlsym(RTLD_NEXT,"gtk_message_dialog_new");
  if(!real_gtk_message_dialog_new_with_markup)
    real_gtk_message_dialog_new_with_markup=(void*(*)(void*,int,int,int,const char*,...))dlsym(RTLD_NEXT,"gtk_message_dialog_new_with_markup");
}

/* ------------ gettext hooks ------------ */
const char* g_dgettext(const char* domain,const char* msgid){
  ensure_syms(); if(!msgid) return msgid; const char* D=dom_of(domain);
  const char* t=try_all(D,msgid); if(t) return t; LOG2("MISS",D,NULL,msgid);
  return rgd?rgd(domain,msgid):msgid;
}
const char* g_dcgettext(const char* domain,const char* msgid,int category){
  ensure_syms(); (void)category; if(!msgid) return msgid; const char* D=dom_of(domain);
  const char* t=try_all(D,msgid); if(t) return t; LOG2("MISS",D,NULL,msgid);
  return rgdc?rgdc(domain,msgid,category):msgid;
}
const char* g_dpgettext2(const char* domain,const char* context,const char* msgid){
  ensure_syms(); if(!msgid) return msgid;
  if(override_allowed_for(domain)){
    char combo[1200];
    if(context&&*context){
      size_t lc=strlen(context), lm=strlen(msgid);
      if(lc+1+lm+1<sizeof(combo)){ memcpy(combo,context,lc); combo[lc]='\004'; memcpy(combo+lc+1,msgid,lm+1); }
      const char* hv=hard_override_core(combo[0]?combo:msgid); if(hv) return hv;
    }else{ const char* hv=hard_override_core(msgid); if(hv) return hv; }
  }
  const char* D=dom_of(domain);
  if(context&&*context){
    char* k=join_ctx(context,msgid);
    if(k){ const char* t=lookup(D,k); if(!t) t=fallback(k); free(k); if(t) return t; }
  }
  const char* t=lookup(D,msgid); if(!t&&msgid[0]=='_') t=lookup(D,msgid+1);
  if(!t) t=fallback(msgid); if(!t&&msgid[0]=='_') t=fallback(msgid+1);
  return t ? t : (rgdp2?rgdp2(domain,context,msgid):msgid);
}

const char* gettext(const char* m){
  ensure_syms(); if(!m) return m; const char* D=dom_of(NULL);
  const char* t=try_all(D,m); return t? t : (r_gettext? r_gettext(m):m);
}
const char* dgettext(const char* d,const char* m){
  ensure_syms(); if(!m) return m; const char* D=dom_of(d);
  const char* t=try_all(D,m); return t? t : (r_dgettext? r_dgettext(d,m):m);
}
const char* dcgettext(const char* d,const char* m,int c){
  ensure_syms(); (void)c; if(!m) return m; const char* D=dom_of(d);
  const char* t=try_all(D,m); return t? t : (r_dcgettext? r_dcgettext(d,m,c):m);
}
const char* ngettext(const char* s,const char* p,unsigned long n){
  ensure_syms(); const char* D=dom_of(NULL);
  const char* t=try_all(D,s); return t? t : (r_ngettext? r_ngettext(s,p,n):(n==1?s:p));
}
const char* dngettext(const char* d,const char* s,const char* p,unsigned long n){
  ensure_syms(); const char* D=dom_of(d);
  const char* t=try_all(D,s); return t? t : (r_dngettext? r_dngettext(d,s,p,n):(n==1?s:p));
}
const char* dcngettext(const char* d,const char* s,const char* p,unsigned long n,int c){
  ensure_syms(); (void)c; const char* D=dom_of(d);
  const char* t=try_all(D,s); return t? t : (r_dcngettext? r_dcngettext(d,s,p,n,c):(n==1?s:p));
}

/* ------------ GTK hooks ------------ */
static void (*real_gtk_window_set_title)(void*,const char*)=NULL;
void gtk_window_set_title(void* win,const char* title){
  if(!real_gtk_window_set_title) real_gtk_window_set_title=(void(*)(void*,const char*))dlsym(RTLD_NEXT,"gtk_window_set_title");
  const char* out=title; const char* hv=hard_override_core(title); if(hv) out=hv;
  real_gtk_window_set_title(win,out);
}

/* MessageDialog 생성: 항상 일반 생성자로 만들고, 마크업이면 set_markup로 강제 적용 */
void* gtk_message_dialog_new(void* parent,int flags,int type,int buttons,const char* fmt,...){
  ensure_syms();
  char buf[2048]; va_list ap; va_start(ap,fmt); vsnprintf(buf,sizeof(buf),fmt,ap); va_end(ap);
  const char* out=buf; const char* hv=hard_override_core(buf); if(hv) out=hv;

  void* dlg = real_gtk_message_dialog_new(parent,flags,type,buttons,"%s",out);

  if (strchr(out,'<') && strchr(out,'>')) {
    gtk_message_dialog_set_markup(dlg, out);
  }
  widen_if_launcher(dlg);
  return dlg;
}

void* gtk_message_dialog_new_with_markup(void* parent,int flags,int type,int buttons,const char* fmt,...){
  ensure_syms();
  char buf[2048]; va_list ap; va_start(ap,fmt); vsnprintf(buf,sizeof(buf),fmt,ap); va_end(ap);
  const char* out=buf; const char* hv=hard_override_core(buf); if(hv) out=hv;

  void* dlg = real_gtk_message_dialog_new(parent,flags,type,buttons,"%s",out);
  gtk_message_dialog_set_markup(dlg, out);

  widen_if_launcher(dlg);
  return dlg;
}

static void (*real_gtk_message_dialog_set_markup)(void*,const char*)=NULL;
void gtk_message_dialog_set_markup(void* dlg,const char* str){
  if(!real_gtk_message_dialog_set_markup)
    real_gtk_message_dialog_set_markup=(void(*)(void*,const char*))dlsym(RTLD_NEXT,"gtk_message_dialog_set_markup");
  const char* out=str; const char* hv=hard_override_core(str); if(hv) out=hv;
  real_gtk_message_dialog_set_markup(dlg,out);
}
static void (*real_gtk_message_dialog_format_secondary_text)(void*,const char*,...)=NULL;
void gtk_message_dialog_format_secondary_text(void* dlg,const char* fmt,...){
  if(!real_gtk_message_dialog_format_secondary_text)
    real_gtk_message_dialog_format_secondary_text=(void(*)(void*,const char*,...))dlsym(RTLD_NEXT,"gtk_message_dialog_format_secondary_text");
  char buf[2048]; va_list ap; va_start(ap,fmt); vsnprintf(buf,sizeof(buf),fmt,ap); va_end(ap);
  const char* out=buf; const char* hv=hard_override_core(buf); if(hv) out=hv;
  real_gtk_message_dialog_format_secondary_text(dlg,"%s",out);
}
static void (*real_gtk_message_dialog_format_secondary_markup)(void*,const char*,...)=NULL;
void gtk_message_dialog_format_secondary_markup(void* dlg,const char* fmt,...){
  if(!real_gtk_message_dialog_format_secondary_markup)
    real_gtk_message_dialog_format_secondary_markup=(void(*)(void*,const char*,...))dlsym(RTLD_NEXT,"gtk_message_dialog_format_secondary_markup");
  char buf[2048]; va_list ap; va_start(ap,fmt); vsnprintf(buf,sizeof(buf),fmt,ap); va_end(ap);
  const char* out=buf; const char* hv=hard_override_core(buf); if(hv) out=hv;
  real_gtk_message_dialog_format_secondary_markup(dlg,"%s",out);
}

/* dialog buttons & labels/menus */
static void* (*real_gtk_dialog_add_button)(void*,const char*,int)=NULL;
void* gtk_dialog_add_button(void* dlg,const char* text,int response){
  if(!real_gtk_dialog_add_button)
    real_gtk_dialog_add_button=(void*(*)(void*,const char*,int))dlsym(RTLD_NEXT,"gtk_dialog_add_button");
  const char* out=text; const char* hv=hard_override_core(text); if(hv) out=hv;
  return real_gtk_dialog_add_button(dlg,out,response);
}
static void (*real_gtk_dialog_add_buttons)(void*,const char*,...)=NULL;
void gtk_dialog_add_buttons(void* dlg,const char* first,...){
  if(!real_gtk_dialog_add_buttons)
    real_gtk_dialog_add_buttons=(void(*)(void*,const char*,...))dlsym(RTLD_NEXT,"gtk_dialog_add_buttons");
  va_list ap; va_start(ap,first);
  const char* texts[16]; int resps[16]; int n=0; const char* t=first;
  while(t && n<16){ int r=va_arg(ap,int); texts[n]=t; resps[n]=r; n++; t=va_arg(ap,const char*); }
  va_end(ap);
  for(int i=0;i<n;i++){
    const char* out=texts[i]; const char* hv=hard_override_core(texts[i]); if(hv) out=hv;
    if(!real_gtk_dialog_add_button)
      real_gtk_dialog_add_button=(void*(*)(void*,const char*,int))dlsym(RTLD_NEXT,"gtk_dialog_add_button");
    real_gtk_dialog_add_button(dlg,out,resps[i]);
  }
}

static void* (*real_gtk_button_new_with_label)(const char*)=NULL;
void* gtk_button_new_with_label(const char* label){
  if(!real_gtk_button_new_with_label)
    real_gtk_button_new_with_label=(void*(*)(const char*))dlsym(RTLD_NEXT,"gtk_button_new_with_label");
  const char* out=label; const char* hv=hard_override_core(label); if(hv) out=hv;
  return real_gtk_button_new_with_label(out);
}
static void* (*real_gtk_button_new_with_mnemonic)(const char*)=NULL;
void* gtk_button_new_with_mnemonic(const char* label){
  if(!real_gtk_button_new_with_mnemonic)
    real_gtk_button_new_with_mnemonic=(void*(*)(const char*))dlsym(RTLD_NEXT,"gtk_button_new_with_mnemonic");
  const char* out=label; const char* hv=hard_override_core(label); if(hv) out=hv;
  return real_gtk_button_new_with_mnemonic(out);
}
static void (*real_gtk_button_set_label)(void*,const char*)=NULL;
void gtk_button_set_label(void* btn,const char* label){
  if(!real_gtk_button_set_label)
    real_gtk_button_set_label=(void(*)(void*,const char*))dlsym(RTLD_NEXT,"gtk_button_set_label");
  const char* out=label; const char* hv=hard_override_core(label); if(hv) out=hv;
  real_gtk_button_set_label(btn,out);
}
static void* (*real_gtk_label_new)(const char*)=NULL;
void* gtk_label_new(const char* str){
  if(!real_gtk_label_new) real_gtk_label_new=(void*(*)(const char*))dlsym(RTLD_NEXT,"gtk_label_new");
  const char* out=str; const char* hv=hard_override_core(str); if(hv) out=hv;
  return real_gtk_label_new(out);
}
static void* (*real_gtk_label_new_with_mnemonic)(const char*)=NULL;
void* gtk_label_new_with_mnemonic(const char* str){
  if(!real_gtk_label_new_with_mnemonic)
    real_gtk_label_new_with_mnemonic=(void*(*)(const char*))dlsym(RTLD_NEXT,"gtk_label_new_with_mnemonic");
  const char* out=str; const char* hv=hard_override_core(str); if(hv) out=hv;
  return real_gtk_label_new_with_mnemonic(out);
}
static void* (*real_gtk_menu_item_new_with_label)(const char*)=NULL;
void* gtk_menu_item_new_with_label(const char* label){
  if(!real_gtk_menu_item_new_with_label)
    real_gtk_menu_item_new_with_label=(void*(*)(const char*))dlsym(RTLD_NEXT,"gtk_menu_item_new_with_label");
  const char* out=label; const char* hv=hard_override_core(label); if(hv) out=hv;
  return real_gtk_menu_item_new_with_label(out);
}
static void* (*real_gtk_menu_item_new_with_mnemonic)(const char*)=NULL;
void* gtk_menu_item_new_with_mnemonic(const char* label){
  if(!real_gtk_menu_item_new_with_mnemonic)
    real_gtk_menu_item_new_with_mnemonic=(void*(*)(const char*))dlsym(RTLD_NEXT,"gtk_menu_item_new_with_mnemonic");
  const char* out=label; const char* hv=hard_override_core(label); if(hv) out=hv;
  return real_gtk_menu_item_new_with_mnemonic(out);
}
static void (*real_gtk_menu_item_set_label)(void*,const char*)=NULL;
void gtk_menu_item_set_label(void* mi,const char* label){
  if(!real_gtk_menu_item_set_label)
    real_gtk_menu_item_set_label=(void(*)(void*,const char*))dlsym(RTLD_NEXT,"gtk_menu_item_set_label");
  const char* out=label; const char* hv=hard_override_core(label); if(hv) out=hv;
  real_gtk_menu_item_set_label(mi,out);
}
static void (*real_gtk_label_set_text)(void*,const char*)=NULL;
void gtk_label_set_text(void* lbl,const char* str){
  if(!real_gtk_label_set_text)
    real_gtk_label_set_text=(void(*)(void*,const char*))dlsym(RTLD_NEXT,"gtk_label_set_text");
  const char* out=str; const char* hv=hard_override_core(str); if(hv) out=hv;
  real_gtk_label_set_text(lbl,out);
}
static void (*real_gtk_label_set_markup)(void*,const char*)=NULL;
void gtk_label_set_markup(void* lbl,const char* str){
  if(!real_gtk_label_set_markup)
    real_gtk_label_set_markup=(void(*)(void*,const char*))dlsym(RTLD_NEXT,"gtk_label_set_markup");
  const char* out=str; const char* hv=hard_override_core(str); if(hv) out=hv;
  real_gtk_label_set_markup(lbl,out);
}
