; This tests some of the subtleties of Phi lowering.  In particular,
; it tests that it does the right thing when it tries to enable
; compare/branch fusing.

; RUN: %p2i -i %s --assemble --disassemble --args -O2 --verbose none \
; RUN:   --phi-edge-split=0 \
; RUN:   | FileCheck %s

define internal i32 @testPhi1(i32 %arg) {
entry:
  %cmp1 = icmp sgt i32 %arg, 0
  br i1 %cmp1, label %next, label %target
next:
  br label %target
target:
  %merge = phi i1 [ %cmp1, %entry ], [ false, %next ]
  %result = zext i1 %merge to i32
  ret i32 %result
}
; Test that compare/branch fusing does not happen, and Phi lowering is
; put in the right place.
; CHECK-LABEL: testPhi1
; CHECK: cmp {{.*}},0x0
; CHECK: mov {{.*}},0x1
; CHECK: jg
; CHECK: mov {{.*}},0x0
; CHECK: mov [[PHI:.*]],
; CHECK: cmp {{.*}},0x0
; CHECK: je
; CHECK: mov [[PHI]],0x0
; CHECK: movzx {{.*}},[[PHI]]

define internal i32 @testPhi2(i32 %arg) {
entry:
  %cmp1 = icmp sgt i32 %arg, 0
  br i1 %cmp1, label %next, label %target
next:
  br label %target
target:
  %merge = phi i32 [ 12345, %entry ], [ 54321, %next ]
  ret i32 %merge
}
; Test that compare/branch fusing and Phi lowering happens as expected.
; CHECK-LABEL: testPhi2
; CHECK: mov {{.*}},0x3039
; CHECK: cmp {{.*}},0x0
; CHECK-NEXT: jle
; CHECK: mov [[PHI:.*]],0xd431
; CHECK: mov {{.*}},[[PHI]]

; Test that address mode inference doesn't extend past
; multi-definition, non-SSA Phi temporaries.
define internal i32 @testPhi3(i32 %arg) {
entry:
  br label %body
body:
  %merge = phi i32 [ %arg, %entry ], [ %elt, %body ]
  %interior = add i32 %merge, 1000
  ; Trick to make a basic block local copy of interior for
  ; addressing mode optimization.
  %interior__4 = add i32 %interior, 0
  %__4 = inttoptr i32 %interior__4 to i32*
  %elt = load i32* %__4, align 1
  %cmp = icmp eq i32 %elt, 0
  br i1 %cmp, label %exit, label %body
exit:
  ; Same trick (making a basic block local copy).
  %interior__6 = add i32 %interior, 0
  %__6 = inttoptr i32 %interior__6 to i32*
  store i32 %arg, i32* %__6, align 1
  ret i32 %arg
}
; I can't figure out how to reliably test this for correctness, so I
; will just include patterns for the entire current O2 sequence.  This
; may need to be changed when meaningful optimizations are added.
; The key is to avoid the "bad" pattern like this:
;
; testPhi3:
; .LtestPhi3$entry:
;         mov     eax, DWORD PTR [esp+4]
;         mov     ecx, eax
; .LtestPhi3$body:
;         mov     ecx, DWORD PTR [ecx+1000]
;         cmp     ecx, 0
;         jne     .LtestPhi3$body
; .LtestPhi3$exit:
;         mov     DWORD PTR [ecx+1000], eax
;         ret
;
; This is bad because the final store address is supposed to be the
; same as the load address in the loop, but it has clearly been
; over-optimized into a null pointer dereference.

; CHECK-LABEL: testPhi3
; CHECK: push [[EBX:.*]]
; CHECK: mov {{.*}},DWORD PTR [esp
; CHECK: mov
; CHECK: mov {{.*}},DWORD PTR [[ADDR:.*0x3e8]]
; CHECK: cmp {{.*}},0x0
; CHECK: jne
; CHECK: mov DWORD PTR [[ADDR]]
; CHECK: pop [[EBX]]
