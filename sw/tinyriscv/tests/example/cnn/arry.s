.section .text
.globl fill_array

# void fill_array(int* src, int* dest, int len)
#
# 参数:
#   a0 - int* src: 指向源int数组的指针
#   a1 - int* dest: 指向目标内存区域的指针
#   a2 - int len: 数组的长度（元素数量）

fill_array:
  # 循环计数器初始化
  mv t0, zero     # t0 = 0，t0用作循环计数器

loop_start:
  # 检查是否达到数组的尾部
  bge t0, a2, loop_end   # 如果 t0 >= len 跳转到循环结束

  # 计算源和目标的偏移量
  slli t1, t0, 2          # t1 = t0 * 4（因为每个int是4个字节）
  add t2, a0, t1         # t2 = src + (t0 * 4)，得到当前元素的地址
  add t3, a1, t1         # t3 = dest + (t0 * 4)，得到目标地址

  # 从源数组复制元素到目标地址
  lw t4, 0(t2)           # t4 = *t2，加载源地址处的int值
  sw t4, 0(t3)           # *t3 = t4，将加载的值存储到目标地址

  # 增加循环计数器
  addi t0, t0, 1         # t0++

  # 继续循环
  j loop_start

loop_end:
  ret                    # 返回到调用者