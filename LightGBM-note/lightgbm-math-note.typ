// LightGBM 数学推导讲义
// 编译：typst compile lightgbm-math-note.typ lightgbm-math-note.pdf

#set document(
  title: "LightGBM 数学推导：从残差到树结构",
  author: "学习笔记",
  date: datetime.today(),
)

#set page(
  paper: "a4",
  margin: (top: 20mm, bottom: 18mm, x: 22mm),
  numbering: "1",
  header: context {
    if counter(page).get().first() > 1 {
      set text(size: 8.5pt, fill: luma(105))
      grid(
        columns: (1fr, auto),
        [LightGBM 数学推导],
        [从 $g,h$ 到节点目标与 Gain],
      )
      line(length: 100%, stroke: 0.35pt + luma(190))
    }
  },
)

#set text(
  font: "Noto Serif SC",
  lang: "zh",
  region: "cn",
  size: 10.5pt,
)
#set par(first-line-indent: 2em, leading: 0.78em, justify: true)
#set heading(numbering: "1.1")
#set math.equation(numbering: "(1)")
#show raw: set text(font: ("Cascadia Mono", "Noto Sans SC"), size: 9pt)
#show link: underline

#show heading: it => {
  v(0.7em)
  set par(first-line-indent: 0em)
  if it.level == 1 {
    block(
      width: 100%,
      inset: (bottom: 4pt),
      stroke: (bottom: 0.8pt + rgb("355a7a")),
    )[
      #text(size: 15pt, weight: "semibold", fill: rgb("244a65"))[
        #if it.numbering != none {
          context counter(heading).display(it.numbering)
          h(0.7em)
        }
        #it.body
      ]
    ]
  } else {
    text(size: 12pt, weight: "semibold", fill: rgb("244a65"))[
      #if it.numbering != none {
        context counter(heading).display(it.numbering)
        h(0.65em)
      }
      #it.body
    ]
  }
}

#let key-box(title, body) = block(
  width: 100%,
  fill: rgb("eef5f8"),
  stroke: 0.7pt + rgb("8db5c7"),
  radius: 4pt,
  inset: 10pt,
  breakable: true,
)[
  #set par(first-line-indent: 0em)
  #text(weight: "semibold", fill: rgb("244a65"))[#title]
  #v(3pt)
  #body
]

#let intuition(body) = block(
  width: 100%,
  fill: luma(247),
  stroke: (left: 2.5pt + rgb("d49b43")),
  inset: (left: 11pt, right: 9pt, y: 8pt),
  breakable: true,
)[
  #set par(first-line-indent: 0em)
  #text(weight: "semibold", fill: rgb("8b5a18"))[直觉]
  #h(0.6em)#body
]

#align(center)[
  #v(9mm)
  #text(size: 22pt, weight: "bold", fill: rgb("244a65"))[
    LightGBM 数学推导
  ]
  #v(4pt)
  #text(size: 14pt, fill: rgb("52758c"))[
    从残差、$g,h$ 到节点目标、$w$、Gain 与区域 $R$
  ]
  #v(10mm)
]

#block(
  width: 100%,
  inset: (x: 14pt, y: 11pt),
  fill: luma(247),
  radius: 4pt,
)[
  #set par(first-line-indent: 0em)
  *摘要：* 本讲义沿一条连续主线推导 LightGBM。已有 $m-1$ 棵树时，我们增加第 $m$ 棵树。新树同时包含叶节点区域 $R_1,dots,R_J$ 与叶节点输出 $w_1,dots,w_J$。损失函数在当前预测处展开后，一阶导数 $g$ 描述修正方向，二阶导数 $h$ 描述局部曲率。把同一叶节点内的样本聚合起来，就得到节点目标函数；对它求导可得最优 $w_j$，比较分裂前后的最优目标值则得到 Gain。平方损失下，每个叶节点拟合该区域内的平均残差。最后，讲义分别说明固定树结构、单步下降与完整 Boosting 过程能够获得什么收敛保证，以及这些保证为何不等于全局最优或实盘有效。
]

#v(7mm)

#key-box([全文路线], [
  $ hat(y)_n^((m-1))
    arrow.r
    f_(m)(bold(x)) = sum_j w_j bb(1)(bold(x) in R_j)
    arrow.r
    (g_n, h_n)
    arrow.r
    cal(L)_(j)(w_j)
    arrow.r
    w_j^star
    arrow.r
    "Gain"
    arrow.r
    R_j $
])

#v(4mm)
#heading(numbering: none)[目录]
#{
  set text(size: 8.4pt)
  set par(leading: 0.45em, first-line-indent: 0em)
  columns(2, gutter: 7mm)[
    #outline(title: none, depth: 2)
  ]
}
#pagebreak()

= 符号与问题设置

设训练集为

$
cal(D) = { (bold(x)_n, y_n) }_(n=1)^N,
$

其中 $bold(x)_n in RR^p$ 是第 $n$ 个样本的特征向量，$y_n$ 是监督目标。在 Qlib 的股票预测任务中，一个样本通常对应“某只股票在某个交易日”，$bold(x)_n$ 是 Alpha158 等因子，$y_n$ 是未来收益标签。

#figure(
  table(
    columns: (1.1fr, 3.8fr),
    inset: 6pt,
    stroke: 0.4pt + luma(205),
    fill: (_, row) => if row == 0 { rgb("e7f0f4") } else { none },
    [*符号*], [*含义*],
    [$bold(x)_n$], [第 $n$ 个样本的 $p$ 维特征],
    [$y_n$], [第 $n$ 个样本的真实标签],
    [$hat(y)_n^((m-1))$], [前 $m-1$ 棵树给出的当前预测],
    [$f_m$], [准备加入的第 $m$ 棵回归树],
    [$R_j$], [第 $j$ 个叶节点覆盖的特征空间区域],
    [$w_j$], [第 $j$ 个叶节点给出的统一修正值],
    [$g_n,h_n$], [损失对当前预测的一阶、二阶导数],
    [$G_j,H_j$], [叶节点内 $g_n,h_n$ 的聚合量],
  ),
  caption: [核心符号表],
)

#key-box([先区分两种权重], [
  本文的 $w_j$ 是树叶节点的输出，不是投资组合权重。LightGBM 先生成股票预测分数，Qlib 的交易策略再把分数转换成持仓权重。两者属于不同阶段。
])

= 第一步：增加第 $m$ 棵树

== 已有模型

已有 $m-1$ 棵树时，模型为

$
F_(m-1)(bold(x)) = sum_(q=1)^(m-1) f_(q)(bold(x)).
$

第 $n$ 个样本的当前预测是

$
hat(y)_n^((m-1)) = F_(m-1)(bold(x)_n).
$

现在加入第 $m$ 棵树：

$
F_(m)(bold(x)) = F_(m-1)(bold(x)) + eta f_(m)(bold(x)),
$

其中 $eta in (0,1]$ 是学习率。为了看清主干推导，下面先令 $eta=1$；最后再把学习率乘回去。

== 一棵树的两个未知部分

具有 $J$ 个叶节点的回归树可以写成

$
f_(m)(bold(x))
= sum_(j=1)^J w_j bb(1)(bold(x) in R_j).
$

这里确实有两类未知量：

- 树结构：$R_1,dots,R_J$；
- 叶节点输出：$w_1,dots,w_J$。

如果 $bold(x)_n in R_j$，则

$
f_(m)(bold(x)_n)=w_j,
$

所以新预测为

$
hat(y)_n^((m)) = hat(y)_n^((m-1)) + w_j.
$

#intuition([
  $R_j$ 回答“哪些样本放在一起”，$w_j$ 回答“这组样本统一修正多少”。LightGBM 并不全局同时枚举所有树，而是贪心构造 $R_j$；一旦某个候选区域确定，$w_j$ 可以解析求出。
])

= 第二步：从损失函数得到 $g$ 和 $h$

== 第 $m$ 轮的原始目标

加入新树以后，希望最小化

$
cal(L)^((m))
= sum_(n=1)^N
  ell(y_n, hat(y)_n^((m-1)) + f_(m)(bold(x)_n))
  + Omega(f_m).
$

为了把结构代价和叶节点正则写进同一个目标，本讲义采用常见的 XGBoost 风格约定：

$
Omega(f_m)
= gamma J + frac(lambda, 2) sum_(j=1)^J w_j^2.
$

#key-box([公式尺度约定], [
  本讲义把节点目标的实际下降量定义为 $frac(1,2)G^2/(H+lambda)$，所以 Gain 公式含有系数 $1/2$。LightGBM 源码在未启用 L1、叶输出限制、路径平滑和单调约束时，叶值仍为 $-G/(H+lambda_2)$，但它把叶得分记为 $G^2/(H+lambda_2)$。因此，当分裂门槛均为零时，LightGBM 模型中的 `split_gain` 是本讲义 Gain 的两倍；两种尺度不会改变候选分裂的排序。本文的 $gamma$ 表示新增叶节点的概念性代价；若要与 LightGBM 的 `min_gain_to_split` 使用相同门槛，应按上述二倍尺度换算。
])

直接优化这个式子困难，因为树结构是离散对象。LightGBM 的关键动作是：在当前预测 $hat(y)_n^((m-1))$ 附近，把每个样本的损失写成关于“新增修正量” $f_(m)(bold(x)_n)$ 的二次函数。

== 一阶导数 $g_n$

对第 $n$ 个样本，把损失写成当前预测 $z$ 的函数：

$
L_(n)(z) = ell(y_n,z).
$

当前所在位置是

$
z = hat(y)_n^((m-1)).
$

定义一阶导数

$
g_n
= frac(partial ell(y_n,hat(y)_n), partial hat(y)_n)
  |_(hat(y)_n = hat(y)_n^((m-1))).
$

$g_n$ 是损失曲线在当前位置的斜率。若 $g_n>0$，增加预测会增加损失，应向下修正；若 $g_n<0$，增加预测会降低损失，应向上修正。因此真正的下降方向是 $-g_n$。

== 二阶导数 $h_n$

定义二阶导数

$
h_n
= frac(partial^2 ell(y_n,hat(y)_n), partial hat(y)_n^2)
  |_(hat(y)_n = hat(y)_n^((m-1))).
$

$h_n$ 描述损失曲线的局部曲率：它衡量梯度随预测值变化得有多快。在一维牛顿法中，局部最优修正是

$
Delta^star = - frac(g,h).
$

这已经预告了 LightGBM 叶节点输出公式为什么会出现“梯度和除以 Hessian 和”。

== 二阶泰勒展开

设新增修正量为

$
Delta_n=f_(m)(bold(x)_n).
$

在当前预测处做二阶泰勒展开：

$
ell(y_n,hat(y)_n^((m-1))+Delta_n)
approx
ell(y_n,hat(y)_n^((m-1)))
+g_n Delta_n
+frac(1,2) h_n Delta_n^2.
$

去掉与新树无关的常数项后，第 $m$ 棵树要优化

$
tilde(cal(L))^((m))
= sum_(n=1)^N
  [g_n f_(m)(bold(x)_n)
  + frac(1,2)h_n f_(m)(bold(x)_n)^2]
  + Omega(f_m).
$

#key-box([$g,h$ 的最短解释], [
  $g_n$ 给出第 $n$ 个样本应该向哪个方向修正；$h_n$ 给出损失在当前位置有多弯，从而缩放修正步长。二者只是损失函数局部二次近似的两个系数。
])

= 平方损失下，$g$ 和 $h$ 就是残差语言

== 直接求导

采用带 $1/2$ 的平方损失：

$
ell(y_n,hat(y)_n)
= frac(1,2)(y_n-hat(y)_n)^2.
$

一阶导数是

$
g_n
= hat(y)_n^((m-1))-y_n.
$

定义当前残差

$
r_n = y_n-hat(y)_n^((m-1)),
$

则

$
(g_n=-r_n).
$

二阶导数是

$
(h_n=1).
$

因此平方损失下，负梯度就是残差：

$
-g_n=r_n=y_n-hat(y)_n^((m-1)).
$

== 不用泰勒公式也能看见它们

加入新树修正 $Delta_n=f_(m)(bold(x)_n)$ 后，新的残差为

$
r_n-Delta_n.
$

平方损失可以精确展开为

$
frac(1,2)(r_n-Delta_n)^2
= frac(1,2)r_n^2-r_n Delta_n+frac(1,2)Delta_n^2.
$

又因为

$
g_n=-r_n, quad h_n=1,
$

所以

$
frac(1,2)(r_n-Delta_n)^2
= underbrace(frac(1,2)r_n^2, "旧模型常数")
+g_n Delta_n
+frac(1,2)h_n Delta_n^2.
$

#intuition([
  对平方损失，二阶展开不是近似，而是精确等式。此时可以完全忘掉抽象的 Hessian：$g_n$ 就是负残差，$h_n$ 恒为 $1$。
])

= 第三步：节点目标函数从哪里来

== 把属于同一叶节点的样本放在一起

设第 $j$ 个叶节点包含的样本索引集合为

$
I_j={n: bold(x)_n in R_j}.
$

对于所有 $n in I_j$，树的输出都相同：

$
f_(m)(bold(x)_n)=w_j.
$

因此这些样本对二阶近似目标的贡献为

$
sum_(n in I_j)
  [g_n w_j+frac(1,2)h_n w_j^2].
$

定义节点聚合量

$
(G_j=sum_(n in I_j)g_n),
quad
(H_j=sum_(n in I_j)h_n).
$

因为同一节点内的 $w_j$ 是共同常数，所以可以提出求和号：

$
sum_(n in I_j)g_n w_j=G_j w_j,
$

$
sum_(n in I_j)frac(1,2)h_n w_j^2
=frac(1,2)H_j w_j^2.
$

再加入 L2 正则项 $lambda w_j^2/2$，得到第 $j$ 个节点的目标函数：

$
(
  tilde(cal(L))_(j)(w_j)
  =G_j w_j+frac(1,2)(H_j+lambda)w_j^2
).
$

整棵树的目标是

$
tilde(cal(L))^((m))
= sum_(j=1)^J
  [G_j w_j+frac(1,2)(H_j+lambda)w_j^2]
  +gamma J.
$

== 求最优叶节点输出 $w_j$

给定区域 $R_j$ 后，$G_j,H_j$ 已知。对节点目标求导：

$
frac(partial tilde(cal(L))_(j), partial w_j)
=G_j+(H_j+lambda)w_j.
$

令导数等于零：

$
G_j+(H_j+lambda)w_j=0.
$

得到

$
(w_j^star=-frac(G_j,H_j+lambda)).
$

平方损失下，$g_n=-r_n$、$h_n=1$，所以

$
G_j=-sum_(n in I_j)r_n,
quad
H_j=|I_j|.
$

于是

$
w_j^star
=frac(sum_(n in I_j)r_n, |I_j|+lambda).
$

当 $lambda=0$ 时：

$
(
  w_j^star
  =frac(1,|I_j|)sum_(n in I_j)
   (y_n-hat(y)_n^((m-1)))
).
$

也就是说，叶节点输出就是该节点内的平均残差。

#key-box([节点目标函数的来源], [
  节点目标函数不是额外假设。它来自三步：先在当前预测处对每个样本的损失做二阶展开；再利用同一叶节点的样本共享 $w_j$；最后把节点内的 $g_n,h_n$ 分别求和为 $G_j,H_j$。
])

= 从节点最优值到 Gain

== 一个节点的最优得分

将

$
w_j^star=-frac(G_j,H_j+lambda)
$

代回节点目标：

$
tilde(cal(L))_(j)(w_j^star)
=-frac(1,2)frac(G_j^2,H_j+lambda).
$

定义节点能够带来的目标下降量为

$
"Score"(I_j)=frac(1,2)frac(G_j^2,H_j+lambda).
$

注意符号关系：最优目标贡献是 $-"Score"$，所以 $"Score"$ 越大，节点通过独立输出 $w_j$ 能降低的损失越多。

== 一个候选分裂的 Gain

设父节点 $I_P$ 被候选条件 $x^((k)) <= s$ 分成

$
I_L={n in I_P:x_n^((k))<=s},
$

$
I_R={n in I_P:x_n^((k))>s}.
$

统计量满足

$
G_P=G_L+G_R,
quad
H_P=H_L+H_R.
$

在本讲义的目标下降量尺度下，分裂收益等于“两个子节点的最优得分”减去“父节点的最优得分”，再减去新增叶节点的复杂度代价：

$
(
"Gain"(k,s)
=frac(1,2)[
  frac(G_L^2,H_L+lambda)
  +frac(G_R^2,H_R+lambda)
  -frac(G_P^2,H_P+lambda)
]-gamma
).
$

LightGBM 在候选特征和阈值中选择

$
(k^star,s^star)=arg max_(k,s) "Gain"(k,s).
$

由这个最佳切分得到两个新区域：

$
R_L=R_P inter {bold(x):x^((k^star))<=s^star},
$

$
R_R=R_P inter {bold(x):x^((k^star))>s^star}.
$

递归分裂后，每个叶节点区域都是路径上若干切分条件的交集：

$
R_j=inter.big_(q in cal(P)_j)
{bold(x):x^((k_q))<=s_q " 或 " x^((k_q))>s_q}.
$

因此，$R_j$ 不是由一个连续方程解析求解，而是由最大 Gain 的贪心切分逐步生成。

= 一个完整的平方损失数值例子

设一个父节点中有四个样本。当前模型的预测与真实值形成残差

$
r=(3,2,-2,-3).
$

平方损失下

$
g=-r=(-3,-2,2,3),
quad h=(1,1,1,1).
$

暂令

$
lambda=0, quad gamma=0.
$

== 不分裂

父节点统计量为

$
G_P=-3-2+2+3=0,
quad H_P=4.
$

父节点最优输出：

$
w_P^star=-frac(0,4)=0.
$

父节点得分：

$
"Score"(I_P)=frac(1,2)frac(0^2,4)=0.
$

这说明正负残差在同一个节点中完全抵消，一个统一的 $w_P$ 无法同时修正它们。

== 候选分裂

假设某个特征阈值把样本分成

$
I_L:{g_1,g_2}=(-3,-2),
$

$
I_R:{g_3,g_4}=(2,3).
$

则

$
G_L=-5, quad H_L=2,
quad
G_R=5, quad H_R=2.
$

左右叶节点输出为

$
w_L^star=-frac(-5,2)=2.5,
quad
w_R^star=-frac(5,2)=-2.5.
$

在本讲义的尺度下，Gain 为

$
"Gain"
=frac(1,2)[frac(25,2)+frac(25,2)-frac(0,4)]
=12.5.
$

若使用 LightGBM 源码的 `split_gain` 尺度，并令 `min_gain_to_split = 0`，同一候选分裂报告的数值是 $25$。两者只相差常数倍，不影响它在候选切分中的排名。

#intuition([
  这个切分把“需要向上修正”的样本与“需要向下修正”的样本分开了。父节点内相互抵消的梯度，进入两个子节点后不再抵消，所以 Gain 很大。
])

= 完整算法：把各部分重新连起来

第 $m$ 轮训练一棵树时，可以按下面的顺序理解：

```text
输入：样本 (x_n, y_n)，已有模型 F_(m-1)

1. 计算当前预测
   y_hat_n = F_(m-1)(x_n)

2. 计算每个样本的局部损失信息
   g_n = d loss / d y_hat_n
   h_n = d² loss / d y_hat_n²

3. 从根节点开始，枚举候选特征和阈值
   对每个候选分裂聚合 G_L, H_L, G_R, H_R

4. 计算每个候选分裂的 Gain
   选择 Gain 最大的分裂，生成新的区域 R_L, R_R

5. 按 leaf-wise 规则继续分裂当前收益最大的叶节点
   直到叶节点数、深度、最小样本数或最小 Gain 触发停止

6. 对每个最终区域 R_j 计算
   w_j = -G_j / (H_j + lambda)

7. 得到新树
   f_m(x) = sum_j w_j 1(x in R_j)

8. 更新模型
   F_m(x) = F_(m-1)(x) + eta f_m(x)
```

需要注意，算法在搜索切分时已经把候选子节点的最优 $w_L,w_R$ 代入目标，因此它能够比较不同候选区域“各自使用最优叶值以后”能降低多少损失。

= 学习率、正则化与停止条件

== 学习率

树计算出的叶节点值是 $w_j$，但模型实际加入的是

$
eta w_j.
$

因此

$
hat(y)_n^((m))
=hat(y)_n^((m-1))+eta w_j,
quad bold(x)_n in R_j.
$

较小的 $eta$ 让每棵树只完成一部分修正，通常需要更多树，但能降低过拟合风险。

== L2 正则化

$lambda$ 出现在分母中：

$
w_j^star=-frac(G_j,H_j+lambda).
$

当 $lambda$ 增大时，叶节点输出绝对值被压缩。它也会降低小样本叶节点的 Gain，使树更保守。

== 结构约束

LightGBM 还通过以下约束控制区域 $R_j$ 的复杂度：

- `num_leaves`：限制叶节点总数 $J$；
- `max_depth`：限制从根到叶的路径长度；
- `min_data_in_leaf`：要求 $|I_j|$ 不得过小；
- `min_gain_to_split`：要求候选 Gain 足够大；
- `feature_fraction`、`bagging_fraction`：随机使用部分特征或样本。

= 收敛性：哪些有保证，哪些没有

LightGBM 的“收敛”不能只用一句话回答。固定树结构时，叶节点值是凸问题的唯一最优解；构造树时，正 Gain 保证局部目标下降；连续增加树时，只有在损失光滑、新树确实提供下降方向且学习率合适等条件下，经验损失才有整体收敛保证。离散树结构仍由贪心搜索产生，所以这些结论不保证全局最优树，也不保证测试集或实盘收益持续改善。

#key-box([分层结论], [
  - 固定 $R_j$：若 $H_j+lambda>0$，$w_j^star$ 是唯一全局最优解；
  - 固定当前轮次：正 Gain 降低二阶近似目标，平方损失下也降低真实目标；
  - 多轮 Boosting：在光滑性、下降方向和步长条件下，训练目标单调下降并收敛；
  - 完整 LightGBM：贪心树搜索不保证得到所有树结构中的全局最优解；
  - 泛化表现：训练损失收敛不等于验证损失、测试损失或实盘表现收敛。
])

== 固定区域 $R_j$ 时，$w_j$ 有唯一最优解

给定叶节点区域 $R_j$，节点目标是

$
tilde(cal(L))_(j)(w_j)
=G_j w_j+frac(1,2)(H_j+lambda)w_j^2.
$

它对 $w_j$ 的二阶导数为

$
frac(partial^2 tilde(cal(L))_(j),partial w_j^2)
=H_j+lambda.
$

只要

$
H_j+lambda>0,
$

节点目标就是严格凸函数，因此驻点

$
w_j^star=-frac(G_j,H_j+lambda)
$

是唯一的全局最优解。这个结论只解决“区域已经给定以后，叶节点应该输出多少”，并没有解决如何全局选择 $R_j$。

== 正 Gain 提供单步下降保证

父节点的最优目标贡献为

$
-frac(1,2)frac(G_P^2,H_P+lambda).
$

候选分裂产生左右子节点后，最优目标贡献变为

$
-frac(1,2)[
  frac(G_L^2,H_L+lambda)
  +frac(G_R^2,H_R+lambda)
].
$

若候选分裂满足

$
"Gain"
=frac(1,2)[
  frac(G_L^2,H_L+lambda)
  +frac(G_R^2,H_R+lambda)
  -frac(G_P^2,H_P+lambda)
]-gamma
>0,
$

那么分裂后的二阶近似正则化目标严格小于分裂前的目标。对于平方损失，二阶展开是精确等式，因此这个结论对本讲义定义的局部正则化目标也是精确的；若只讨论不带正则的经验平方损失，仍应结合实际叶值与学习率检查更新后的损失变化。对于一般损失，Gain 衡量的是当前预测附近的局部二阶模型；学习率和正则化负责限制修正幅度，使局部近似保持可靠。

== 多棵树是函数空间中的近似梯度下降

定义经验风险

$
cal(L)(F)=sum_(n=1)^N ell(y_n,F(bold(x)_n)).
$

Boosting 更新为

$
F_(m)=F_(m-1)+eta f_(m).
$

假设 $cal(L)$ 的梯度是 $beta$-Lipschitz 的，即

$
norm(nabla cal(L)(F)-nabla cal(L)(G))
<=beta norm(F-G).
$

下降引理给出

$
cal(L)(F_(m-1)+eta f_(m))
<=cal(L)(F_(m-1))
+eta ⟨nabla cal(L)(F_(m-1)),f_(m)⟩
+frac(beta eta^2,2)norm(f_(m))^2.
$

如果新树与负梯度方向具有正相关性：

$
⟨nabla cal(L)(F_(m-1)),f_(m)⟩<0,
$

并且 $eta$ 足够小，那么右侧新增的两项之和为负，因此

$
cal(L)(F_(m))<cal(L)(F_(m-1)).
$

这里的新树不需要等于完整负梯度。它只需要与负梯度保持足够的对齐，就能成为一个下降方向；决策树的作用正是近似这个方向。

== 平方损失下的精确下降条件

定义第 $m-1$ 轮的残差向量

$
bold(r)_(m-1)=bold(y)-F_(m-1)(bold(X)).
$

平方损失为

$
cal(L)(F_(m-1))=frac(1,2)norm(bold(r)_(m-1))^2.
$

加入新树以后

$
bold(r)_m=bold(r)_(m-1)-eta bold(f)_m,
$

其中 $bold(f)_m$ 表示新树在全部训练样本上的输出向量。于是

$
cal(L)(F_m)-cal(L)(F_(m-1))
=-eta ⟨bold(r)_(m-1),bold(f)_m⟩
+frac(eta^2,2)norm(bold(f)_m)^2.
$

只要新树与残差正相关：

$
⟨bold(r)_(m-1),bold(f)_m⟩>0,
$

并且学习率满足

$
0<eta<
frac(
  2 ⟨bold(r)_(m-1),bold(f)_m⟩,
  norm(bold(f)_m)^2
),
$

就有

$
cal(L)(F_m)<cal(L)(F_(m-1)).
$

这个不等式直接说明学习率的作用：即使树找到了正确方向，步长过大仍可能越过局部最低点，使损失反而上升。

== 当新树是残差的投影

为了看见一个更简洁的充分条件，假设新树输出向量是残差在某个树函数空间上的正交投影：

$
bold(f)_m=P_(cal(T))bold(r)_(m-1).
$

正交投影满足

$
⟨bold(r)_(m-1),bold(f)_m⟩
=norm(bold(f)_m)^2.
$

代入损失变化式：

$
cal(L)(F_m)-cal(L)(F_(m-1))
=-eta(1-frac(eta,2))norm(bold(f)_m)^2.
$

因此只要

$
0<eta<2,
$

训练损失就不会增加。实际算法使用的回归树通常只是近似投影，但这个结果解释了为什么较小的学习率能让 Boosting 迭代更稳定。

== 训练目标何时整体收敛

若每轮都能找到下降方向、学习率满足下降条件、损失函数存在下界，那么

$
cal(L)(F_0)>=cal(L)(F_1)>=dots>=inf_F cal(L)(F).
$

训练目标构成一个单调递减且有下界的数列，因此目标值收敛到某个有限值。这个结论本身不说明极限等于全局最优值，也不说明梯度或模型参数一定收敛。

要进一步得到收敛率，还需要一个统一的“弱学习”条件。存在常数 $delta>0$，使每一轮的树都满足

$
-frac(
  ⟨nabla cal(L)(F_(m-1)),f_(m)⟩,
  norm(nabla cal(L)(F_(m-1))) norm(f_(m))
)>=delta.
$

这个条件要求新树与负梯度的夹角余弦始终存在正下界。若目标凸且光滑，同时弱学习条件与步长规则成立，常见分析可以给出次线性收敛率；若目标强凸或满足 Polyak-Lojasiewicz 条件，在同样的方向质量和步长条件下可以得到线性收敛率。仅凭“凸且光滑”不能推出这些速率。若目标非凸，通常只能讨论梯度趋近于零或算法趋向驻点。

如果当前树空间无法继续解释残差，弱学习条件就可能失效，新树输出会接近零，训练过程也会停在该函数空间能够达到的水平。

== 为什么没有全局最优树保证

区域 $R_1,dots,R_J$ 来自离散树结构。LightGBM 在每个节点选择当前 Gain 最大的特征与阈值：

$
(k^star,s^star)=arg max_(k,s) "Gain"(k,s).
$

这个选择只保证当前节点的局部最优分裂。一旦早期切分确定，后续区域只能在该结构上继续生长；另一条早期 Gain 略低的路径，可能最终形成整体更优的树。因此 LightGBM 不保证

$
F_M=arg min_(F " 属于全部树集成") cal(L)(F).
$

它保证的是若干可计算的局部下降步骤，而不是组合树结构上的全局最优性。

== 必须区分三种“收敛”

#figure(
  table(
    columns: (1.35fr, 2.25fr, 1.9fr),
    inset: 6pt,
    stroke: 0.4pt + luma(205),
    fill: (_, row) => if row == 0 { rgb("e7f0f4") } else { none },
    [*对象*], [*能够说明什么*], [*不能推出什么*],
    [训练目标收敛], [经验损失趋向有限值], [不推出全局最优或泛化有效],
    [模型参数收敛], [树结构与输出最终稳定], [损失收敛不必伴随参数收敛],
    [测试或实盘收敛], [未见样本上的表现稳定], [不能由训练损失单独保证],
  ),
  caption: [三种收敛概念不能混用],
)

分类数据完全可分时，逻辑损失可能趋近于零，而模型分数的绝对值继续增大。这说明“损失收敛”不必意味着“参数收敛”。同样，训练损失持续下降时，验证损失可能先下降后上升。这就是 Qlib 工作流使用验证集和 early stopping 的原因：

$
m^star=arg min_m cal(L)_("valid")(F_m).
$

#key-box([最终结论], [
  LightGBM 对固定叶节点值有严格凸优化保证，对正 Gain 分裂有局部下降保证，对整个 Boosting 序列有依赖光滑性、弱学习条件与步长选择的训练目标收敛保证。它没有无条件的全局最优树保证，也没有从训练收敛直接推导测试集或实盘表现的保证。
])

= 与 Qlib 股票预测的对应关系

在当前 Qlib LightGBM 工作流中，可以把数学对象对应为：

#figure(
  table(
    columns: (1.6fr, 3.4fr),
    inset: 6pt,
    stroke: 0.4pt + luma(205),
    fill: (_, row) => if row == 0 { rgb("e7f0f4") } else { none },
    [*数学对象*], [*Qlib 中的含义*],
    [$bold(x)_(i,t)$], [股票 $i$ 在交易日 $t$ 的 Alpha158 因子],
    [$y_(i,t)$], [配置文件定义的未来收益标签],
    [$hat(y)_(i,t)$], [LightGBM 输出的股票预测分数],
    [$R_j$], [满足一组因子阈值条件的股票-日期样本集合],
    [$w_j$], [该样本集合在当前 Boosting 轮次中的统一分数修正],
    [$f_m$], [第 $m$ 棵树对全部股票-日期样本的修正函数],
  ),
  caption: [数学对象与 Qlib 工作流的对应],
)

LightGBM 最终输出

$
hat(y)_(i,t)=F_(M)(bold(x)_(i,t)).
$

Qlib 再按同一天的预测分数排序，并由 TopK 等策略生成投资组合。树的 $w_j$ 并不是最终持仓权重。

= 容易混淆的三个问题

== LightGBM 是否同时求 $w$ 和 $R$

从优化目标看，它们都是未知量：

$
min_({R_j},{w_j}) cal(L).
$

但实际算法不做全局联合求解。它对每个候选分裂解析计算最优叶值，再用 Gain 贪心选择切分。可以概括为：

$
"候选 " R
arrow.r
"解析最优 " w
arrow.r
"计算 Gain"
arrow.r
"选择最佳 " R.
$

== $g,h$ 是模型参数吗

不是。$g_n,h_n$ 是当前轮次中，每个样本的损失函数局部信息。模型更新后，它们会重新计算。平方损失下：

$
g_n=hat(y)_n-y_n,
quad h_n=1.
$

== Gain 是熵或基尼指数吗

不是。LightGBM 回归树的 Gain 是二阶近似目标函数的下降量。它由 $G,H$ 决定，而不是分类树中的信息熵。

#pagebreak()
= 一页公式总结

#key-box([模型], [
  $
  F_(m)(bold(x))=F_(m-1)(bold(x))+eta f_(m)(bold(x)),
  $
  $
  f_(m)(bold(x))=sum_(j=1)^J w_j bb(1)(bold(x) in R_j).
  $
])

#key-box([样本梯度与 Hessian], [
  $
  g_n=frac(partial ell,partial hat(y)_n),
  quad
  h_n=frac(partial^2 ell,partial hat(y)_n^2).
  $
  平方损失下：$g_n=hat(y)_n-y_n=-r_n$，$h_n=1$。
])

#key-box([节点聚合与目标], [
  $
  G_j=sum_(n in I_j)g_n,
  quad
  H_j=sum_(n in I_j)h_n,
  $
  $
  tilde(cal(L))_(j)(w_j)
  =G_j w_j+frac(1,2)(H_j+lambda)w_j^2.
  $
])

#key-box([最优叶节点输出], [
  $
  (w_j^star=-frac(G_j,H_j+lambda)).
  $
  平方损失且 $lambda=0$ 时，$w_j^star$ 是节点内平均残差。
])

#key-box([分裂收益（本讲义尺度）], [
  $
  (
  "Gain"
  =frac(1,2)[
    frac(G_L^2,H_L+lambda)
    +frac(G_R^2,H_R+lambda)
    -frac(G_P^2,H_P+lambda)
  ]-gamma
  ).
  $
  LightGBM 在默认二阶叶得分尺度下报告的 `split_gain` 是该下降量的两倍；分裂排序不变。
])

#v(6mm)
#align(center)[
  #text(size: 9pt, fill: luma(110))[
    结论：平方损失下，LightGBM 每轮寻找能把不同残差模式分开的树区域，并用区域内平均残差修正已有模型。
  ]
]
